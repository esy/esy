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

let addPackage ~state (pkg : Package.t) =
  state.universe <- (Universe.add ~pkg state.universe);
  ()

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
    let%bind reasons = RunAsync.ofRun (SolveExplain.explain ~cudfMapping ~root cudf) in
    let%lwt () =
      Logs_lwt.err
        (fun m ->
          m "@[<v>No solution found (possible explanations below):@\n%a@]"
          SolveExplain.ppReasons reasons) in
    error "no solution found"

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
