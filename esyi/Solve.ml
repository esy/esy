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

module Strategies = struct
  let trendy = "-removed,-notuptodate,-new"
end

let runSolver ?(strategy=Strategies.trendy) ~cfg ~univ root =
  let open RunAsync.Syntax in
  let cudfUniverse, cudfMapping = Universe.toCudf univ in

  let cudfRoot = Universe.CudfMapping.encodePkgExn root cudfMapping in

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

  let request = {
    Cudf.default_request with
    install = [cudfRoot.Cudf.package, Some (`Eq, cudfRoot.Cudf.version)]
  } in
  let preamble = Cudf.default_preamble in

  let solution =
    let cudf =
      Some preamble, Cudf.get_packages cudfUniverse, request
    in
    let dataIn = printCudfDoc cudf in
    let%bind dataOut = Fs.withTempFile ~data:dataIn (fun filename ->
      let cmd = Cmd.(
        cfg.Config.esySolveCmd
        % ("--strategy=" ^ strategy)
        % ("--timeout=" ^ string_of_float(cfg.solveTimeout))
        % p filename) in
      ChildProcess.runOut cmd
    ) in
    return (parseCudfSolution dataOut)
  in

  match%lwt solution with

  | Error _ ->
    let cudf = preamble, cudfUniverse, request in
    begin match%bind SolveExplain.explain ~cudfMapping ~root cudf with
    | Some reasons ->
      Logs_lwt.err
        (fun m ->
          m "@[<v>No solution found (possible explanations below):@\n%a@]"
          SolveExplain.ppReasons reasons);%lwt
      error "no solution found"
    | None ->
      error "no solution found"
    end

  | Ok (_preamble, universe) ->

    let cudfPackagesToInstall =
      Cudf.get_packages
        ~filter:(fun p -> p.Cudf.installed)
        universe
    in

    let packagesToInstall =
      cudfPackagesToInstall
      |> List.map ~f:(fun p -> Universe.CudfMapping.decodePkgExn p cudfMapping)
      |> List.filter ~f:(fun p -> p.Package.name <> root.Package.name)
    in

    return (Some packagesToInstall)

let getPackageCached ~state name version =
  let open RunAsync.Syntax in
  let key = (name, version) in
  Cache.Packages.compute (state.cache).pkgs key begin fun _ ->
    let%bind manifest =
      match version with
      | Version.Source (Source.LocalPath _) -> error "not implemented"
      | Version.Source (Git _) -> error "not implemented"
      | Version.Source (Github (user, repo, ref)) ->
        begin match%bind Package.Github.getManifest ~user ~repo ~ref () with
        | Package.PackageJson manifest ->
          return (Package.PackageJson ({ manifest with name }))
        | manifest -> return manifest
        end
      | Version.Source Source.NoSource -> error "no source"
      | Version.Source (Source.Archive _) -> error "not implemented"
      | Version.Npm version ->
        let%bind manifest = NpmRegistry.version ~cfg:(state.cfg) name version in
        return (Package.PackageJson manifest)
      | Version.Opam version ->
        let name = OpamFile.PackageName.ofNpmExn name in
        begin match%bind OpamRegistry.version state.cache.opamRegistry ~name ~version with
          | Some manifest ->
            return (Package.Opam manifest)
          | None -> error ("no such opam package: " ^ OpamFile.PackageName.toString name)
        end
    in
    let%bind pkg = RunAsync.ofRun (Package.make ~version manifest) in
    return pkg
  end

let getAvailableVersions ~state:(state : t)  (req : Req.t) =
  let open RunAsync.Syntax in
  let cache = state.cache in
  let name = Req.name req in
  let spec = Req.spec req in
  match spec with

  | VersionSpec.Npm formula ->
    let%bind available =
      Cache.NpmPackages.compute cache.availableNpmVersions name begin fun name ->
        let%lwt () = Logs_lwt.app (fun m -> m "Resolving %s" name) in
        let%bind versions = NpmRegistry.versions ~cfg:(state.cfg) name in
        let () =
          let cacheManifest (version, manifest) =
            let version = PackageInfo.Version.Npm version in
            let key = (name, version) in
            Cache.Packages.ensureComputed cache.pkgs key begin fun _ ->
              Lwt.return (Package.make ~version (Package.PackageJson manifest))
            end
          in
          List.iter ~f:cacheManifest versions
        in
        return versions
      end
    in
    available
    |> List.sort ~cmp:(fun (va, _) (vb, _) -> NpmVersion.Version.compare va vb)
    |> List.filter ~f:(fun (version, _json) -> NpmVersion.Formula.DNF.matches formula ~version)
    |> List.map ~f:(
        fun (version, _json) ->
          let version = PackageInfo.Version.Npm version in
          let%bind pkg = getPackageCached ~state name version in
          return pkg
        )
    |> RunAsync.List.joinAll

  | VersionSpec.Opam semver ->
    let%bind available =
      Cache.OpamPackages.compute cache.availableOpamVersions name begin fun name ->
        let%lwt () = Logs_lwt.app (fun m -> m "Resolving %s" name) in
        let%bind opamName = RunAsync.ofRun (OpamFile.PackageName.ofNpm name) in
        let%bind info = OpamRegistry.versions (state.cache).opamRegistry ~name:opamName in
        return info
      end
    in

    let available =
      List.sort
        ~cmp:(fun (va, _) (vb, _) -> OpamVersion.Version.compare va vb)
        available
    in

    let matched =
      List.filter
        ~f:(fun (version, _path) -> OpamVersion.Formula.DNF.matches semver ~version)
        available
    in

    let matched =
      if matched = []
      then
        List.filter
          ~f:(fun (version, _path) -> OpamVersion.Formula.DNF.matches semver ~version)
          available
      else matched
    in

    matched
    |> List.map
        ~f:(fun (version, _path) ->
            let version = PackageInfo.Version.Opam version in
            let%bind pkg = getPackageCached ~state name version in
            return pkg)
    |> RunAsync.List.joinAll

  | VersionSpec.Source (SourceSpec.Github (user, repo, ref) as srcSpec) ->
      let%bind source =
        Cache.Sources.compute (state.cache).sources srcSpec begin fun _ ->
          let%lwt () = Logs_lwt.app (fun m -> m "Resolving %s" (Req.toString req)) in
          let%bind ref =
            match ref with
            | Some ref -> return ref
            | None ->
              let remote =
                Printf.sprintf (("https://github.com/%s/%s")
                  [@reason.raw_literal
                    "https://github.com/%s/%s"]) user repo in
              Git.lsRemote ~remote ()
          in
          return (Source.Github (user, repo, ref))
        end
      in
      let version = Version.Source source in
      let%bind pkg = getPackageCached ~state name version in
      return [pkg]

  | VersionSpec.Source (SourceSpec.Git _) ->
    let%lwt () = Logs_lwt.app (fun m -> m "Resolving %s" (Req.toString req)) in
    error "git dependencies are not supported"

  | VersionSpec.Source SourceSpec.NoSource ->
    let%lwt () = Logs_lwt.app (fun m -> m "Resolving %s" (Req.toString req)) in
    error "no source dependencies are not supported"

  | VersionSpec.Source (SourceSpec.Archive _) ->
    let%lwt () = Logs_lwt.app (fun m -> m "Resolving %s" (Req.toString req)) in
    error "archive dependencies are not supported"

  | VersionSpec.Source (SourceSpec.LocalPath p) ->
    let%lwt () = Logs_lwt.app (fun m -> m "Resolving %s" (Req.toString req)) in
    let version = Version.Source (Source.LocalPath p) in
    let%bind pkg = getPackageCached ~state name version in
    return [pkg]

let initState ~cfg  ?cache  ~resolutions  root =
  let open RunAsync.Syntax in

  let rewritePkgWithResolutions (pkg : Package.t) =
    let rewriteReq req =
      match PackageInfo.Resolutions.apply resolutions req with
      | Some req -> req
      | None -> req
    in
    {
      pkg with
      dependencies = {
        pkg.dependencies with
        dependencies =
          List.map ~f:rewriteReq pkg.dependencies.dependencies
      }
    }
  in

  let%bind state = make ?cache ~cfg () in

  let rec addPkg (pkg : Package.t) =
    if not (Universe.mem ~pkg state.universe)
    then
      let pkg = rewritePkgWithResolutions pkg in
      state.universe <- Universe.add ~pkg state.universe;
      pkg.dependencies.dependencies
      |> List.map ~f:addReq
      |> RunAsync.List.waitAll
    else return ()

  and addReq req =
    let%bind versions =
      getAvailableVersions ~state req
      |> RunAsync.withContext ("processing request: " ^ Req.toString req)
    in
    versions
    |> List.map ~f:addPkg
    |> RunAsync.List.waitAll
  in

  let%bind () = addPkg root in
  return state

let solve ~cfg  ~resolutions  (root : Package.t) =
  let open RunAsync.Syntax in
  let%bind state = initState ~cfg ~resolutions root in
  let%bind dependencies =
    match%bind runSolver ~cfg ~univ:state.universe root with
    | None -> error "Unable to resolve dependencies"
    | Some packages -> return packages
  in
  let solution = Solution.make ~root ~dependencies in
  return solution
