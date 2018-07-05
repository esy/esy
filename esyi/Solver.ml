module Source = Package.Source
module SourceSpec = Package.SourceSpec
module Version = Package.Version
module VersionSpec = Package.VersionSpec
module Dependencies = Package.Dependencies
module Req = Package.Req
module Resolutions = Package.Resolutions

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

module Explanation = struct

  type t = reason list

  and reason =
    | Conflict of chain * chain
    | Missing of chain * Resolver.Resolution.t list

  and chain =
    Req.t * Package.t list

  let empty = []

  let pp fmt reasons =

    let ppEm pp = Fmt.styled `Bold pp in
    let ppErr pp = Fmt.styled `Bold (Fmt.styled `Red pp) in

    let ppChain fmt (req, path) =
      let ppPkgName fmt pkg = Fmt.string fmt pkg.Package.name in
      let sep = Fmt.unit " -> " in
      Fmt.pf fmt
        "@[<v>%a@,(required by %a)@]"
        (ppErr Req.pp) req Fmt.(list ~sep (ppEm ppPkgName)) (List.rev path)
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

  let collectReasons ~resolver ~cudfMapping ~root reasons =
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
      match Dependencies.findByName ~name requestor.Package.dependencies with
      | Some req -> req
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
      let seenConflictFor reqa reqb reasons =
        let f = function
          | Conflict ((ereqa, _), (ereqb, _)) ->
            Req.(toString ereqa = toString reqa && toString ereqb = toString reqb)
          | Missing _ -> false
        in
        List.exists ~f reasons
      in
      let seenMissingFor req reasons =
        let f = function
          | Missing ((ereq, _), _) ->
            Req.(toString req = toString ereq)
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
              let%bind _req, available =
                let req = Req.make ~name:(Req.name req) ~spec:"*" in
                Resolver.resolve ~req resolver
              in
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

  let rewriteReq req =
    match Package.Resolutions.apply solver.resolutions req with
    | Some req -> req
    | None -> req
  in

  let rewritePkgWithResolutions (pkg : Package.t) =
    {
      pkg with
      dependencies = Dependencies.map ~f:rewriteReq pkg.dependencies
    }
  in

  let universe = ref solver.universe in
  let report, finish = solver.cfg.Config.createProgressReporter ~name:"resolving" () in

  let rec addPkg (pkg : Package.t) =
    if not (Universe.mem ~pkg !universe)
    then
      match pkg.kind with
      | Package.Esy ->
        let pkg = rewritePkgWithResolutions pkg in
        universe := Universe.add ~pkg !universe;
        let%bind dependencies =
          pkg.dependencies
          |> Dependencies.toList
          |> List.map ~f:addReq
          |> RunAsync.List.joinAll
        in
        let pkg = {pkg with dependencies = Dependencies.ofList dependencies} in
        universe := Universe.add ~pkg !universe;
        return ()
      | Package.Npm -> return ()
    else return ()

  and addReq req =
    let%lwt () =
      let status = Format.asprintf "%a" Req.pp req in
      report status
    in
    let%bind req, resolutions =
      Resolver.resolve ~req solver.resolver
      |> RunAsync.withContext ("resolving request: " ^ Req.toString req)
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

    return req
  in

  let%bind dependencies =
    let%bind dependencies =
      dependencies
      |> Dependencies.toList
      |> List.map ~f:(fun req ->
          let req = rewriteReq req in
          addReq req)
      |> RunAsync.List.joinAll
    in
    return (Dependencies.(addMany ~reqs:dependencies empty))
  in

  let%lwt () = finish () in

  return ({solver with universe = !universe}, dependencies)

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
    source = Source.NoSource;
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

  let resolveOfInstalled req =
    let spec = Req.spec req in
    let name = Req.name req in

    let rec findFirstMatching = function
      | [] -> None
      | pkg::pkgs ->
        if VersionSpec.matches ~version:pkg.Package.version spec
        then Some pkg
        else findFirstMatching pkgs
    in

    findFirstMatching (Hashtbl.find_all installed name)
  in

  let resolveOfOutside req =
    let spec = Req.spec req in

    let rec findFirstMatching = function
      | [] -> None
      | res::rest ->
        if VersionSpec.matches ~version:res.Resolver.Resolution.version spec
        then Some res
        else findFirstMatching rest
    in

    let%lwt () =
      let status = Format.asprintf "%a" Req.pp req in
      report status
    in
    let%bind _req, resolutions = Resolver.resolve ~req solver.resolver in
    let resolutions = List.rev resolutions in
    match findFirstMatching resolutions with
    | Some resolution ->
      let%bind pkg = Resolver.package ~resolution solver.resolver in
      return (Some pkg)
    | None -> return None
  in

  let resolve req =
    let%bind pkg =
      match resolveOfInstalled req with
      | None -> begin match%bind resolveOfOutside req with
        | None ->
          let msg = Format.asprintf "unable to find a match for %a" Req.pp req in
          error msg
        | Some pkg -> return pkg
        end
      | Some pkg -> return pkg
    in
    return pkg
  in

  let rec solveDependencies ~seen dependencies =

    (** This prefetches resolutions which can result in an overfetch but makes
     * things happen much faster. *)
    let%bind _ =
      let f req = Resolver.resolve ~req solver.resolver in
      dependencies
      |> Dependencies.toList
      |> List.map ~f
      |> RunAsync.List.joinAll
    in

    let f roots req =
      let name = Req.name req in
      if StringSet.mem name seen
      then return roots
      else begin
        let seen = StringSet.add name seen in
        let%bind pkg = resolve req in
        addToInstalled pkg;
        let%bind dependencies = solveDependencies ~seen pkg.Package.dependencies in
        let record = Solution.Record.ofPackage pkg in
        let root = Solution.make record dependencies in
        return (root::roots)
      end
    in
    dependencies
    |> Dependencies.toList
    |> RunAsync.List.foldLeft ~f ~init:[]
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

  let%bind solver, dependencies =
    (* we override dependencies with devDependencies form the root project *)
    let dependencies =
      Dependencies.overrideMany
        ~reqs:(Dependencies.toList root.devDependencies)
        root.dependencies
    in
    let%bind solver = make ~cfg ~resolutions () in
    let%bind solver, dependencies = add ~dependencies solver in
    return (solver, dependencies)
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

  let solution =
    Solution.make (Solution.Record.ofPackage root)
    dependencies
  in

  return solution
