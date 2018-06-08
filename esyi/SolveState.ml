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
  type t = {
    cudfVersionToVersion: ((string * int), PackageInfo.Version.t) Hashtbl.t ;
    versionToCudfVersion: ((string * PackageInfo.Version.t), int) Hashtbl.t
  }

  let make ?(size=100) () = {
    cudfVersionToVersion = Hashtbl.create size;
    versionToCudfVersion = Hashtbl.create size;
  }

  let update t name realVersion version =
    Hashtbl.replace t.versionToCudfVersion (name, realVersion) version;
    Hashtbl.replace t.cudfVersionToVersion (name, version) realVersion

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
          "Tried to find a package that wasn't listed in the version map %s@cudf:%i"
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
