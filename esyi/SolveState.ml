module VersionSpec = PackageInfo.VersionSpec
module Req = PackageInfo.Req

module Cache = struct
  module Packages = Memoize.Make(struct
    type key = (string * PackageInfo.Version.t)
    type value = Package.t RunAsync.t
  end)

  module NpmPackages = Memoize.Make(struct
    type key = string
    type value = (NpmVersion.Version.t * PackageJson.t) list RunAsync.t
  end)

  module OpamPackages = Memoize.Make(struct
    type key = string
    type value = (OpamVersion.Version.t * OpamFile.ThinManifest.t) list RunAsync.t
  end)

  type t = {
    opamRegistry: OpamRegistry.t;
    npmPackages: (string, Yojson.Safe.json) Hashtbl.t;
    opamPackages: (string, OpamFile.manifest) Hashtbl.t;

    pkgs: Packages.t;
    availableNpmVersions: NpmPackages.t;
    availableOpamVersions: OpamPackages.t;
  }

  let make ~cfg () =
    let open RunAsync.Syntax in
    let%bind opamRegistry = OpamRegistry.init ~cfg () in
    return {
      availableNpmVersions = NpmPackages.make ();
      availableOpamVersions = OpamPackages.make ();
      opamRegistry;
      npmPackages = Hashtbl.create(100);
      opamPackages = Hashtbl.create(100);
      pkgs = Packages.make ();
    }

end

module VersionMap = struct

  module VersionSet = Set.Make(Package.Version)

  type t = {
    cudfVersionToVersion: ((string * int), PackageInfo.Version.t) Hashtbl.t ;
    versionToCudfVersion: ((string * PackageInfo.Version.t), int) Hashtbl.t;
    versions : (string, VersionSet.t) Hashtbl.t;
  }

  let make ?(size=100) () = {
    cudfVersionToVersion = Hashtbl.create size;
    versionToCudfVersion = Hashtbl.create size;
    versions = Hashtbl.create size;
  }

  let update map name version cudfVersion =
    Hashtbl.replace map.versionToCudfVersion (name, version) cudfVersion;
    Hashtbl.replace map.cudfVersionToVersion (name, cudfVersion) version;
    let () =
      let versions =
        try Hashtbl.find map.versions name
        with _ -> VersionSet.empty
      in
      let versions = VersionSet.add version versions in
      Hashtbl.replace map.versions name versions
    in
    ()

  let findVersion ~name ~cudfVersion map =
    match Hashtbl.find map.cudfVersionToVersion (name, cudfVersion) with
    | exception Not_found -> None
    | version -> Some version

  let findCudfVersion ~name ~version map =
    match Hashtbl.find map.versionToCudfVersion (name, version) with
    | exception Not_found -> None
    | version -> Some version

  let findVersionExn ~name ~cudfVersion map =
    match findVersion ~name ~cudfVersion map with
    | Some v -> v
    | None ->
      let msg =
        Printf.sprintf
          "Tried to find a package that wasn't listed in the version map %s@cudf:%i\n"
          name cudfVersion
      in
      failwith msg

  let findCudfVersionExn ~name ~version map =
    match findCudfVersion ~name ~version map with
    | Some v -> v
    | None ->
      let msg =
        Printf.sprintf
          "Tried to find a package that wasn't listed in the version map %s@%s"
          name (PackageInfo.Version.toString version)
      in
      failwith msg

end

type t = {
  cfg: Config.t;
  cache: Cache.t;
  versionMap: VersionMap.t;
  universe: Cudf.universe;
}

let make ?cache ~cfg () =
  let open RunAsync.Syntax in
  let%bind cache =
    match cache with
    | Some cache -> return cache
    | None -> Cache.make ~cfg ()
  in
  return {
    cfg;
    cache;
    versionMap = VersionMap.make ();
    universe = Cudf.empty_universe();
  }


let matchesSource req cudfVersions package =
  let version =
    VersionMap.findVersionExn
      cudfVersions
      ~name:package.Cudf.package
      ~cudfVersion:package.Cudf.version
  in
  VersionSpec.satisfies ~version req


let cudfDep owner universe cudfVersions req =
  let name = Req.name req in
  let spec = Req.spec req in

  let available = Cudf.lookup_packages universe name in
  let matching = List.filter (matchesSource spec cudfVersions) available in

  let final =
    if matching = []
    then
      let hack =
        match spec with
        | Opam _ ->
          List.filter (matchesSource spec cudfVersions) available
        | _ -> []
      in
      match hack, name with
      | [], "ocaml" -> []
      | [], _ ->
        Printf.printf
          "[ERROR]: requirement unsatisfiable: %s wants %s@%s but available:\n"
          owner name (VersionSpec.toString spec);

        List.iter
          (fun pkg ->
            let version =
              VersionMap.findVersionExn
                cudfVersions
                ~name:pkg.Cudf.package
                ~cudfVersion:pkg.Cudf.version
            in
            Printf.printf " - %s\n" (PackageInfo.Version.toString version))
          available;

        []
      | matching, _ -> matching
    else matching
  in
  let final =
    List.map
      (fun package -> package.Cudf.package, Some (`Eq, package.Cudf.version))
      final
  in
  match final with
  | [] ->
    let name = "**not-a-package**" in
    [name, Some (`Eq, 10000000000)]
  | final -> final

let addPackage ~state  ~previouslyInstalled  ~deep ~cudfVersion (pkg : Package.t) =
  VersionMap.update state.versionMap pkg.name pkg.version cudfVersion;

  Cache.Packages.put state.cache.pkgs (pkg.name, pkg.version) (RunAsync.return pkg);

  let package =
    let installed = match previouslyInstalled with
      | None -> false
      | Some table ->
        Hashtbl.mem table (pkg.name, pkg.version)
    in
    let depends = match deep with
      | true ->
          let from =
            Printf.sprintf "%s (at %s)"
              pkg.name
              (PackageInfo.Version.toString pkg.version)
          in
          List.map
            (cudfDep from state.universe state.versionMap)
            pkg.dependencies.dependencies
      | false -> []
    in
    {
      Cudf.default_package with
      package = pkg.name;
      version = cudfVersion;
      conflicts = [pkg.name, None];
      installed;
      depends;
    }
  in Cudf.add_package state.universe package
