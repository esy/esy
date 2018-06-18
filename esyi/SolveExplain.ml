module Req = PackageInfo.Req
module Version = PackageInfo.Version

type reasons = reason list

and reason =
  | Conflict of chain * chain
  | Missing of chain * Version.t list

and chain =
  Req.t * Package.t list

let collectReasons ~cudfMapping ~root reasons =

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
          conflict::reasons
        else reasons
      | Algo.Diagnostic.Missing (pkg, vpkglist) ->
        let pkg = Universe.CudfMapping.decodePkgExn pkg cudfMapping in
        let requestor, path = resolveDepChain pkg in
        let f reasons (name, _) =
          let req = resolveReq name pkg in
          if not (seenMissingFor req reasons)
          then
            let chain = (req, pkg::requestor::path) in
            let available =
              Universe.CudfMapping.univ cudfMapping
              |> Universe.findVersions ~name
              |> List.map ~f:(fun p -> p.Package.version)
            in
            let missing = Missing (chain, available) in
            missing::reasons
          else reasons
        in
        List.fold_left ~f ~init:reasons vpkglist
      | _ -> reasons
    in
    List.fold_left ~f ~init:[] reasons
  in

  reasons

let explain ~cudfMapping ~root cudf =
  let open Run.Syntax in
  begin match Algo.Depsolver.check_request ~explain:true cudf with
  | Algo.Depsolver.Error err -> error err
  | Algo.Depsolver.Sat  _ ->
    failwith "incostistent state: dose and mccs have different opinion"
  | Algo.Depsolver.Unsat None ->
    failwith "incostistent state: no explanation available"
  | Algo.Depsolver.Unsat (Some { result = Algo.Diagnostic.Success _; _ }) ->
    failwith "incostistent state: dose reports success"
  | Algo.Depsolver.Unsat (Some { result = Algo.Diagnostic.Failure reasons; _ }) ->
    let reasons = reasons () in
    return (collectReasons ~cudfMapping ~root reasons)
  end

let ppEm pp =
  Fmt.styled `Bold pp

let ppErr pp =
  Fmt.styled `Bold (Fmt.styled `Red pp)

let ppChain fmt (req, path) =
  let ppPkgName fmt pkg = Fmt.string fmt pkg.Package.name in
  let sep = Fmt.unit " <- " in
  Fmt.pf fmt
    "@[<v>%a@,(required by %a)@]"
    (ppErr Req.pp) req Fmt.(list ~sep (ppEm ppPkgName)) path

let ppReason fmt = function
  | Missing (chain, available) ->
    Fmt.pf fmt
      "No packages matching:@;@[<v 2>@;%a@;@;Versions available:@;@[<v 2>@;%a@]@]"
      ppChain chain
      (Fmt.list Version.pp) available
  | Conflict (chaina, chainb) ->
    Fmt.pf fmt
      "@[<v 2>Conflicting dependencies:@;@%a@;%a@]"
      ppChain chaina ppChain chainb

let ppReasons fmt reasons =
  let sep = Fmt.unit "@;@;" in
  Fmt.pf fmt "@[<v>%a@;@]" (Fmt.list ~sep ppReason) reasons
