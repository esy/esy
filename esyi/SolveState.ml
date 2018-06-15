module Source = PackageInfo.Source
module SourceSpec = PackageInfo.SourceSpec
module Version = PackageInfo.Version
module VersionSpec = PackageInfo.VersionSpec
module Req = PackageInfo.Req
module Resolutions = PackageInfo.Resolutions

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

  module Sources = Memoize.Make(struct
    type key = SourceSpec.t
    type value = Source.t RunAsync.t
  end)

  type t = {
    opamRegistry: OpamRegistry.t;
    npmPackages: (string, Yojson.Safe.json) Hashtbl.t;
    opamPackages: (string, OpamFile.manifest) Hashtbl.t;

    pkgs: Packages.t;
    sources: Sources.t;

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
      sources = Sources.make ();
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
          "inconsistent state: found a package not in the cudf version map %s@cudf:%i\n"
          name cudfVersion
      in
      failwith msg

  let findCudfVersionExn ~name ~version map =
    match findCudfVersion ~name ~version map with
    | Some v -> v
    | None ->
      let msg =
        Printf.sprintf
          "inconsistent state: found a package not in the cudf version map %s@%s"
          name (PackageInfo.Version.toString version)
      in
      failwith msg

end

module Universe = struct

  type t = Package.t Version.Map.t StringMap.t

  let empty = StringMap.empty

  let add ~pkg (univ : t) =
    let {Package. name; version; _} = pkg in
    let versions =
      match StringMap.find_opt name univ with
      | None -> Version.Map.empty
      | Some versions -> versions
    in
    StringMap.add name (Version.Map.add version pkg versions) univ

  let mem ~pkg univ =
    match StringMap.find pkg.Package.name univ with
    | None -> false
    | Some versions -> Version.Map.mem pkg.Package.version versions

  let findVersion ~name ~version (univ : t) =
    match StringMap.find name univ with
    | None -> None
    | Some versions -> Version.Map.find_opt version versions

  let findVersions ~name univ =
    match StringMap.find name univ with
    | None -> []
    | Some versions ->
      versions
      |> Version.Map.bindings
      |> List.map ~f:(fun (_, pkg) -> pkg)

  module CudfName = struct

    let escapeWith = "UuU"
    let underscoreRe = Re.(compile (char '_'))
    let underscoreEscapeRe = Re.(compile (str escapeWith))

    let ofString name =
      Re.replace_string underscoreRe ~by:escapeWith name

    let toString name =
      Re.replace_string underscoreEscapeRe ~by:"_" name
  end

  let toCudf univ =
    let cudfUniv = Cudf.empty_universe () in
    let cudfVersionMap = VersionMap.make () in

    (* We add packages in batch by name so this "set of package names" is
     * enough to check if we have handled a pkg already.
     *)
    let seen, markAsSeen =
      let names = ref StringSet.empty in
      let seen name = StringSet.mem name !names in
      let markAsSeen name = names := StringSet.add name !names in
      seen, markAsSeen
    in

    let updateVersionMap pkgs =
      let f cudfVersion (pkg : Package.t) =
        VersionMap.update
          cudfVersionMap
          pkg.name
          pkg.version
          (cudfVersion + 1);
      in
      List.iteri ~f pkgs;
    in

    let rec encodePkg (pkg : Package.t) =
      let cudfVersion =
        VersionMap.findCudfVersionExn
          ~name:pkg.name
          ~version:pkg.version
          cudfVersionMap
      in

      let depends = List.map ~f:(encodeReq ~from:pkg) pkg.dependencies.dependencies in
      let cudfName = CudfName.ofString pkg.name in
      let cudfPkg = {
        Cudf.default_package with
        package = cudfName;
        version = cudfVersion;
        conflicts = [cudfName, None];
        installed = false;
        depends;
      }
      in
      Cudf.add_package cudfUniv cudfPkg

    and encodeReq ~from req =
      let name = Req.name req in
      let spec = Req.spec req in

      let versions = findVersions ~name univ in

      if not (seen name) then (
        markAsSeen name;
        updateVersionMap versions;
      );

      let versionsMatched =
        List.filter
          ~f:(fun pkg -> VersionSpec.satisfies ~version:pkg.Package.version spec)
          versions
      in

      if versionsMatched = [] && name <> "ocaml" then begin
          let printAvailableVersions () =
            List.iter
              ~f:(fun pkg -> Printf.printf " - %s\n" (PackageInfo.Version.toString pkg.Package.version))
              versions
          in

          Printf.printf
            "[ERROR]: requirement unsatisfiable: %s@%s wants %s@%s but available:\n"
            from.Package.name
            (Version.toString from.Package.version)
            name
            (VersionSpec.toString spec);

          printAvailableVersions ();
      end;

      match versionsMatched with
      | [] ->
        let name = "NOTAREALPACKAGE" in
        [name, Some (`Eq, 10000000000)]
      | versionsMatched ->
        let pkgToConstraint pkg =
          let cudfVersion =
            VersionMap.findCudfVersionExn
              ~name:pkg.Package.name
              ~version:pkg.Package.version
              cudfVersionMap
          in
          CudfName.ofString pkg.Package.name, Some (`Eq, cudfVersion)
        in
        List.map ~f:pkgToConstraint versionsMatched
    in

    StringMap.iter (fun name _ ->
      let versions = findVersions ~name univ in
      updateVersionMap versions;
      List.iter ~f:encodePkg versions;
    ) univ;

    cudfUniv, cudfVersionMap

  let toCudfUniverse univ =
    let cudfUniv, _ = toCudf univ in
    cudfUniv

end

type t = {
  cfg: Config.t;
  cache: Cache.t;
  mutable universe: Universe.t;
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
    universe = Universe.empty;
  }

let addPackage ~state (pkg : Package.t) =
  state.universe <- (Universe.add ~pkg state.universe);
  ()

module Strategies = struct
  let trendy = "-removed,-notuptodate,-new"
end

let runSolver ?(strategy=Strategies.trendy) ~cfg ~univ root =
  let open RunAsync.Syntax in
  let cudfUniverse, cudfVersionMap = Universe.toCudf univ in

  let cudfName = root.Package.name in
  let cudfVersion =
    VersionMap.findCudfVersionExn
      ~name:(root.Package.name)
      ~version:(root.Package.version)
      cudfVersionMap
  in

  let printCudfDoc doc =
    let o = IO.output_string () in
    Cudf_printer.pp_io_doc o doc;
    IO.close_out o
  in

  let parseCudfSolution data =
    let i = IO.input_string data in
    let p = Cudf_parser.from_IO_in_channel i in
    let solution = Cudf_parser.load_solution p cudfUniverse in
    IO.close_in i;
    solution
  in

  let%bind solution =
    let doc =
      let request = {
        Cudf.default_request with
        install = [cudfName, Some (`Eq, cudfVersion)]
      } in
      let preamble = Cudf.default_preamble in
      Some preamble, Cudf.get_packages cudfUniverse, request
    in
    let dataIn = printCudfDoc doc in
    let%bind () = Fs.writeFile ~data:dataIn Path.(v "./input.cudf") in
    let%bind dataOut = Fs.withTempFile ~data:dataIn (fun filename ->
      let cmd = Cmd.(cfg.Config.esySolveCmd % "--" % strategy % p filename) in
      ChildProcess.runOut cmd
    ) in
    return (Some (parseCudfSolution dataOut))
  in

  match solution with
  | None -> return None
  | Some (_preamble, universe) ->

    let cudfPackagesToInstall =
      Cudf.get_packages
        ~filter:(fun p -> p.Cudf.installed)
        universe
    in

    let packagesToInstall =
      cudfPackagesToInstall
      |> List.filter ~f:(fun p -> Universe.CudfName.toString p.Cudf.package <> root.Package.name)
      |> List.map ~f:(fun p ->
          let name = Universe.CudfName.toString p.Cudf.package in
          let version =
            VersionMap.findVersionExn
              ~name
              ~cudfVersion:p.Cudf.version
              cudfVersionMap
          in
          match Universe.findVersion ~name ~version univ with
          | Some pkg -> pkg
          | None ->
            let msg = Printf.sprintf
              "inconsistent state: missing package %s@%s"
              name (Version.toString version)
            in
            failwith msg)
    in

    return (Some packagesToInstall)
