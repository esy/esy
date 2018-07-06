module Source = Package.Source
module SourceSpec = Package.SourceSpec
module Version = Package.Version
module VersionSpec = Package.VersionSpec
module Dependencies = Package.Dependencies
module Req = Package.Req
module Resolutions = Package.Resolutions
module DepFormula = Package.DepFormula

module Strategy = struct
  let trendy = "-removed,-notuptodate,-new"
  (* let minimalAddition = "-removed,-changed,-notuptodate" *)
end

type t = {
  cfg : Config.t;
  resolver : Resolver.t;
  universe : Universe.t;
  resolutions : Resolutions.t;
}

let ppDepFormula fmt = function
  | DepFormula.Npm _ -> Fmt.unit "npm" fmt ()
  | DepFormula.Opam _ -> Fmt.unit "opam" fmt ()
  | DepFormula.Source srcSpec -> SourceSpec.pp fmt srcSpec

module Explanation = struct

  type t = reason list

  and reason =
    | Conflict of chain * chain
    | Missing of chain * Resolver.Resolution.t list

  and chain =
    Package.Dependencies.t * Package.t list

  let empty = []

  let pp fmt reasons =

    let ppEm pp = Fmt.styled `Bold pp in
    let ppErr pp = Fmt.styled `Bold (Fmt.styled `Red pp) in

    let ppChain fmt (req, path) =
      let ppPkgName fmt pkg = Fmt.string fmt pkg.Package.name in
      let sep = Fmt.unit " -> " in
      Fmt.pf fmt
        "@[<v>%a@,(required by %a)@]"
        (ppErr Dependencies.pp) req Fmt.(list ~sep (ppEm ppPkgName)) (List.rev path)
    in

    let ppReason fmt = function
      | Missing (chain, available) ->
        Fmt.pf fmt
          "No packages matching:@;@[<v 2>@;%a@;@;Versions available:@;@[<v 2>@;%a@]@]"
          ppChain chain
          (Fmt.list Resolver.Resolution.pp) available
      | Conflict (chaina, chainb) ->
        Fmt.pf fmt
          "@[<v 2>Conflicting dependencies:@;@%a@;%a@]"
          ppChain chaina ppChain chainb
    in

    let sep = Fmt.unit "@;@;" in
    Fmt.pf fmt "@[<v>%a@;@]" (Fmt.list ~sep ppReason) reasons

  let collectReasons ~resolver:_ ~cudfMapping ~root reasons =
    let open RunAsync.Syntax in

    (* Find a pair of requestor, path for the current package.
    * Note that there can be multiple paths in the dependency graph but we only
    * consider one of them.
    *)
    let resolveDepChain =

      let map =
        let f map = function
          | Algo.Diagnostic.Dependency (pkg, _, _) when pkg.Cudf.package = "dose-dummy-request" -> map
          | Algo.Diagnostic.Dependency (pkg, _, deplist) ->
            let pkg = Universe.CudfMapping.decodePkgExn pkg cudfMapping in
            let f map dep =
              let dep = Universe.CudfMapping.decodePkgExn dep cudfMapping in
              Package.Map.add dep pkg map
            in
            List.fold_left ~f ~init:map deplist
          | _ -> map
        in
        let map = Package.Map.empty in
        List.fold_left ~f ~init:map reasons
      in

      let resolve pkg =
        if pkg.Package.name = root.Package.name
        then failwith "inconsistent state: root package was not expected"
        else
          let rec aux path pkg =
            match Package.Map.find_opt pkg map with
            | None -> pkg::path
            | Some npkg -> aux (pkg::path) npkg
          in
          match List.rev (aux [] pkg) with
          | []
          | _::[] -> failwith "inconsistent state: empty dep path"
          | _::requestor::path -> (requestor, path)
      in

      resolve
    in

    let resolveReq name requestor =
      match Dependencies.subformulaForPackage ~name requestor.Package.dependencies with
      | Some deps -> deps
      | None ->
        let msg = Printf.sprintf "inconsistent state: no request found for %s" name in
        failwith msg
    in

    let resolveReqViaDepChain pkg =
      let requestor, path = resolveDepChain pkg in
      let req = resolveReq pkg.name requestor in
      (req, requestor, path)
    in

    let reasons =
      let seenConflictFor depsa depsb reasons =
        let f = function
          | Conflict ((edepsa, _), (edepsb, _)) ->
            Dependencies.(show edepsa = show depsa && show edepsb = show depsb)
          | Missing _ -> false
        in
        List.exists ~f reasons
      in
      let seenMissingFor deps reasons =
        let f = function
          | Missing ((edeps, _), _) ->
            Dependencies.(show deps = show edeps)
          | Conflict _ -> false
        in
        List.exists ~f reasons
      in
      let f reasons = function
        | Algo.Diagnostic.Conflict (pkga, pkgb, _) ->
          let pkga = Universe.CudfMapping.decodePkgExn pkga cudfMapping in
          let pkgb = Universe.CudfMapping.decodePkgExn pkgb cudfMapping in
          let reqa, requestora, patha = resolveReqViaDepChain pkga in
          let reqb, requestorb, pathb = resolveReqViaDepChain pkgb in
          if not (seenConflictFor reqa reqb reasons)
          then
            let conflict = Conflict ((reqa, requestora::patha), (reqb, requestorb::pathb)) in
            return (conflict::reasons)
          else return reasons
        | Algo.Diagnostic.Missing (pkg, vpkglist) ->
          let pkg = Universe.CudfMapping.decodePkgExn pkg cudfMapping in
          let path =
            if pkg.Package.name = root.Package.name
            then []
            else
              let requestor, path = resolveDepChain pkg in
              requestor::path
          in
          let f reasons (name, _) =
            let name = Universe.CudfMapping.decodePkgName name in
            let req = resolveReq name pkg in
            if not (seenMissingFor req reasons)
            then
              let chain = (req, pkg::path) in
              (* let%bind _req, available = *)
              (*   let req = Req.make ~name:(Req.name req) ~spec:"*" in *)
              (*   Resolver.resolve ~req resolver *)
              (* in *)
              let available = [] in (* TODO *)
              let missing = Missing (chain, available) in
              return (missing::reasons)
            else return reasons
          in
          RunAsync.List.foldLeft ~f ~init:reasons vpkglist
        | _ -> return reasons
      in
      RunAsync.List.foldLeft ~f ~init:[] reasons
    in

    reasons

  let explain ~resolver ~cudfMapping ~root cudf =
    let open RunAsync.Syntax in
    begin match Algo.Depsolver.check_request ~explain:true cudf with
    | Algo.Depsolver.Sat  _
    | Algo.Depsolver.Unsat None
    | Algo.Depsolver.Unsat (Some { result = Algo.Diagnostic.Success _; _ }) ->
      return None
    | Algo.Depsolver.Unsat (Some { result = Algo.Diagnostic.Failure reasons; _ }) ->
      let reasons = reasons () in
      let%bind reasons = collectReasons ~resolver ~cudfMapping ~root reasons in
      return (Some reasons)
    | Algo.Depsolver.Error err -> error err
    end

end

let solutionRecordOfPkg ~solver (pkg : Package.t) =
  let open RunAsync.Syntax in
  let%bind source =
    match pkg.source with
    | Package.Source source -> return source
    | Package.SourceSpec sourceSpec ->
      Resolver.resolveSource ~name:pkg.name ~sourceSpec solver.resolver
  in

  let%bind files =
    match pkg.opam with
    | Some opam -> opam.files ()
    | None -> return []
  in

  let manifest =
    match pkg.opam with
    | Some opam -> Some opam.manifest
    | None -> None
  in

  return {
    Solution.Record.
    name = pkg.name;
    version = pkg.version;
    source;
    manifest;
    files;
  }

let make ~cfg ?resolver ~resolutions () =
  let open RunAsync.Syntax in

  let%bind resolver =
    match resolver with
    | Some resolver -> return resolver
    | None -> Resolver.make ~cfg ()
  in

  let universe = ref Universe.empty in

  return {cfg; resolver; universe = !universe; resolutions}

let add ~(dependencies : Dependencies.t) solver =
  let open RunAsync.Syntax in

  let rewriteDepsWithResolutions deps =
    let f dep =
      match Package.Resolutions.apply solver.resolutions dep with
      | Some dep -> dep
      | None -> dep
    in
    Dependencies.mapDeps ~f deps
  in

  let universe = ref solver.universe in
  let report, finish = solver.cfg.Config.createProgressReporter ~name:"resolving" () in

  let rec addPkg (pkg : Package.t) =
    if not (Universe.mem ~pkg !universe)
    then
      match pkg.kind with
      | Package.Esy ->
        universe := Universe.add ~pkg !universe;
        let%bind () = addDependencies pkg.dependencies in
        universe := Universe.add ~pkg !universe;
        return ()
      | Package.Npm -> return ()
    else return ()

  and addDependencies dependencies =
    dependencies
    |> rewriteDepsWithResolutions
    |> Dependencies.describeByPackageName
    |> List.map ~f:(fun (name, formula) -> addNameWithFormula name formula)
    |> RunAsync.List.waitAll

  and addNameWithFormula name formula =
    let%lwt () =
      let status = Format.asprintf "%s" name in
      report status
    in
    let%bind resolutions =
      Resolver.resolve ~name ~formula solver.resolver
    in

    let%bind packages =
      resolutions
      |> List.map ~f:(fun resolution -> Resolver.package ~resolution solver.resolver)
      |> RunAsync.List.joinAll
    in

    let%bind () =
      packages
      |> List.map ~f:addPkg
      |> RunAsync.List.waitAll
    in

    return ()
  in

  let%bind () = addDependencies dependencies in

  let%lwt () = finish () in

  (* TODO: return rewritten deps *)
  return {solver with universe = !universe}

let printCudfDoc doc =
  let o = IO.output_string () in
  Cudf_printer.pp_io_doc o doc;
  IO.close_out o

let parseCudfSolution ~cudfUniverse data =
  let i = IO.input_string data in
  let p = Cudf_parser.from_IO_in_channel i in
  let solution = Cudf_parser.load_solution p cudfUniverse in
  IO.close_in i;
  solution

let solveDependencies ~installed ~strategy dependencies solver =
  let open RunAsync.Syntax in

  let dummyRoot = {
    Package.
    name = "ROOT";
    version = Version.parseExn "0.0.0";
    source = Package.Source Source.NoSource;
    opam = None;
    dependencies;
    devDependencies = Dependencies.empty;
    kind = Esy;
  } in

  let universe = Universe.add ~pkg:dummyRoot solver.universe in
  let cudfUniverse, cudfMapping = Universe.toCudf ~installed universe in
  let cudfRoot = Universe.CudfMapping.encodePkgExn dummyRoot cudfMapping in

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
        solver.cfg.Config.esySolveCmd
        % ("--strategy=" ^ strategy)
        % ("--timeout=" ^ string_of_float(solver.cfg.solveTimeout))
        % p filename) in
      ChildProcess.runOut cmd
    ) in
    return (parseCudfSolution ~cudfUniverse dataOut)
  in

  match%lwt solution with

  | Error _ ->
    let cudf = preamble, cudfUniverse, request in
    begin match%bind
      Explanation.explain
        ~resolver:solver.resolver
        ~cudfMapping
        ~root:dummyRoot
        cudf
    with
    | Some reasons -> return (Error reasons)
    | None -> return (Error Explanation.empty)
    end

  | Ok (_preamble, cudfUniv) ->

    let packages =
      cudfUniv
      |> Cudf.get_packages ~filter:(fun p -> p.Cudf.installed)
      |> List.map ~f:(fun p -> Universe.CudfMapping.decodePkgExn p cudfMapping)
      |> List.filter ~f:(fun p -> p.Package.name <> dummyRoot.Package.name)
      |> Package.Set.of_list
    in

    return (Ok packages)

let solveDependenciesNaively
  ~(installed : Package.Set.t)
  (dependencies : Dependencies.t)
  (solver : t) =
  let open RunAsync.Syntax in

  let report, finish = solver.cfg.Config.createProgressReporter ~name:"resolving" () in

  let installed =
    let tbl = Hashtbl.create 100 in
    Package.Set.iter (fun pkg -> Hashtbl.add tbl pkg.name pkg) installed;
    tbl
  in

  let addToInstalled pkg =
    Hashtbl.add installed pkg.Package.name pkg
  in

  let resolveOfInstalled name formula =

    let rec findFirstMatching = function
      | [] -> None
      | pkg::pkgs ->
        if Package.DepFormula.matches ~version:pkg.Package.version formula
        then Some pkg
        else findFirstMatching pkgs
    in

    findFirstMatching (Hashtbl.find_all installed name)
  in

  let resolveOfOutside name formula =
    let rec findFirstMatching = function
      | [] -> None
      | res::rest ->
        if Package.DepFormula.matches ~version:res.Resolver.Resolution.version formula
        then Some res
        else findFirstMatching rest
    in

    let%lwt () =
      let status = Format.asprintf "%s@%a" name ppDepFormula formula in
      report status
    in
    let%bind resolutions = Resolver.resolve ~name ~formula solver.resolver in
    let resolutions = List.rev resolutions in
    match findFirstMatching resolutions with
    | Some resolution ->
      let%bind pkg = Resolver.package ~resolution solver.resolver in
      return (Some pkg)
    | None -> return None
  in

  let resolve name formula =
    let%bind pkg =
      match resolveOfInstalled name formula with
      | None -> begin match%bind resolveOfOutside name formula with
        | None ->
          let msg = Format.asprintf "unable to find a match for %s" name in
          error msg
        | Some pkg -> return pkg
        end
      | Some pkg -> return pkg
    in
    return pkg
  in

  let rec solveDependencies ~seen dependencies =

    let dependenciesByName =
      dependencies
      |> Dependencies.describeByPackageName
    in

    (** This prefetches resolutions which can result in an overfetch but makes
     * things happen much faster. *)
    let%bind _ =
      dependenciesByName
      |> List.map ~f:(fun (name, formula) -> Resolver.resolve ~name ~formula solver.resolver)
      |> RunAsync.List.joinAll
    in

    let f roots (name, formula) =
      if StringSet.mem name seen
      then return roots
      else begin
        let seen = StringSet.add name seen in
        let%bind pkg = resolve name formula in
        addToInstalled pkg;
        let%bind dependencies = solveDependencies ~seen pkg.Package.dependencies in
        let%bind record = solutionRecordOfPkg ~solver pkg in
        let root = Solution.make record dependencies in
        return (root::roots)
      end
    in
    RunAsync.List.foldLeft ~f ~init:[] dependenciesByName
  in

  let%bind roots = solveDependencies ~seen:StringSet.empty dependencies in
  finish ();%lwt
  return roots

let solve ~cfg ~resolutions (root : Package.t) =
  let open RunAsync.Syntax in

  let getResultOrExplain = function
    | Ok dependencies -> return dependencies
    | Error explanation ->
      let msg = Format.asprintf
        "@[<v>No solution found:@;@;%a@]"
        Explanation.pp explanation
      in
      error msg
  in

  let dependencies =
    (* we conj dependencies with devDependencies for the root project *)
    root.dependencies @ root.devDependencies
  in

  let%bind solver =
    let%bind solver = make ~cfg ~resolutions () in
    let%bind solver = add ~dependencies solver in
    return solver
  in

  (* Solve runtime dependencies first *)
  let%bind installed =
    let%bind res =
      solveDependencies
        ~installed:Package.Set.empty
        ~strategy:Strategy.trendy
        dependencies
        solver
    in getResultOrExplain res
  in

  let%bind dependencies =
    solveDependenciesNaively
      ~installed
      dependencies
      solver
  in

  let%bind solution =
    let%bind record = solutionRecordOfPkg ~solver root in
    return (Solution.make record dependencies)
  in

  return solution
