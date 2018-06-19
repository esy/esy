module Source = PackageInfo.Source
module SourceSpec = PackageInfo.SourceSpec
module Version = PackageInfo.Version
module VersionSpec = PackageInfo.VersionSpec
module Req = PackageInfo.Req
module Resolutions = PackageInfo.Resolutions

module Strategy = struct
  type t = string
  let trendy = "-removed,-notuptodate,-new"
end

type t = {
  cfg: Config.t;
  resolver : Resolver.t;
  universe: Universe.t;
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
      List.find
        ~f:(fun req -> Req.name req = name)
        requestor.Package.dependencies.dependencies
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
              let%bind available =
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

type solveResult = (Solution.t, Explanation.t) result

let make ~cfg ?resolver ~resolutions root =
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

  let%bind resolver =
    match resolver with
    | Some resolver -> return resolver
    | None -> Resolver.make ~cfg ()
  in

  let universe = ref Universe.empty in

  let rec addPkg (pkg : Package.t) =
    if not (Universe.mem ~pkg !universe)
    then
      let pkg = rewritePkgWithResolutions pkg in
      universe := Universe.add ~pkg !universe;
      pkg.dependencies.dependencies
      |> List.map ~f:addReq
      |> RunAsync.List.waitAll
    else return ()

  and addReq req =
    let%bind resolutions =
      Resolver.resolve ~req resolver
      |> RunAsync.withContext ("resolving request: " ^ Req.toString req)
    in

    let%bind packages =
      resolutions
      |> List.map ~f:(fun resolution -> Resolver.package ~resolution resolver)
      |> RunAsync.List.joinAll
    in

    packages
    |> List.map ~f:addPkg
    |> RunAsync.List.waitAll;
  in

  let%bind () = addPkg root in
  return {cfg; resolver; universe = !universe}

let solve ?(strategy=Strategy.trendy) ~root solver =
  let open RunAsync.Syntax in

  let cudfUniverse, cudfMapping = Universe.toCudf solver.universe in

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
        solver.cfg.Config.esySolveCmd
        % ("--strategy=" ^ strategy)
        % ("--timeout=" ^ string_of_float(solver.cfg.solveTimeout))
        % p filename) in
      ChildProcess.runOut cmd
    ) in
    return (parseCudfSolution dataOut)
  in

  match%lwt solution with

  | Error _ ->
    let cudf = preamble, cudfUniverse, request in
    begin match%bind Explanation.explain ~resolver:solver.resolver ~cudfMapping ~root cudf with
    | Some reasons -> return (Error reasons)
    | None -> return (Error Explanation.empty)
    end

  | Ok (_preamble, cudfUniv) ->

    let dependencies =
      cudfUniv
      |> Cudf.get_packages ~filter:(fun p -> p.Cudf.installed)
      |> List.map ~f:(fun p -> Universe.CudfMapping.decodePkgExn p cudfMapping)
      |> List.filter ~f:(fun p -> p.Package.name <> root.Package.name)
    in

    let solution = Solution.make ~root ~dependencies in
    return (Ok solution)
