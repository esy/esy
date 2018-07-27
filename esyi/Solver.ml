module Source = Package.Source
module SourceSpec = Package.SourceSpec
module Version = Package.Version
module VersionSpec = Package.VersionSpec
module Dependencies = Package.Dependencies
module NpmDependencies = Package.NpmDependencies
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

  module Reason = struct

    type t =
      | Conflict of {left : chain; right : chain}
      | Missing of {name : string; path : chain; available : Resolver.Resolution.t list}
      [@@deriving ord]

    and chain =
      Package.t list

    let ppChain fmt path =
      let ppPkgName fmt pkg = Fmt.string fmt pkg.Package.name in
      let sep = Fmt.unit " -> " in
      Fmt.pf fmt "%a" Fmt.(list ~sep ppPkgName) (List.rev path)

    let pp fmt = function
      | Missing {name; path; available;} ->
        Fmt.pf fmt
          "No packages matching:@;@[<v 2>@;%s (required by %a)@;@;Versions available:@;@[<v 2>@;%a@]@]"
          name
          ppChain path
          (Fmt.list Resolver.Resolution.pp) available
      | Conflict {left; right;} ->
        Fmt.pf fmt
          "@[<v 2>Conflicting dependencies:@;@%a@;%a@]"
          ppChain left ppChain right

    module Set = Set.Make(struct
      type nonrec t = t
      let compare = compare
    end)
  end

  type t = Reason.t list

  let empty = []

  let pp fmt reasons =
    let sep = Fmt.unit "@;@;" in
    Fmt.pf fmt "@[<v>%a@;@]" (Fmt.list ~sep Reason.pp) reasons

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

    let resolveReqViaDepChain pkg =
      let requestor, path = resolveDepChain pkg in
      (requestor, path)
    in

    let%bind reasons =
      let f reasons = function
        | Algo.Diagnostic.Conflict (pkga, pkgb, _) ->
          let pkga = Universe.CudfMapping.decodePkgExn pkga cudfMapping in
          let pkgb = Universe.CudfMapping.decodePkgExn pkgb cudfMapping in
          let requestora, patha = resolveReqViaDepChain pkga in
          let requestorb, pathb = resolveReqViaDepChain pkgb in
          let conflict = Reason.Conflict {left = requestora::patha; right = requestorb::pathb} in
          if not (Reason.Set.mem conflict reasons)
          then return (Reason.Set.add conflict reasons)
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
            let%lwt available =
              match%lwt Resolver.resolve ~name resolver with
              | Ok (available, _) -> Lwt.return available
              | Error _ -> Lwt.return []
            in
            let missing = Reason.Missing {name; path = pkg::path; available} in
            if not (Reason.Set.mem missing reasons)
            then return (Reason.Set.add missing reasons)
            else return reasons
          in
          RunAsync.List.foldLeft ~f ~init:reasons vpkglist
        | _ -> return reasons
      in
      RunAsync.List.foldLeft ~f ~init:Reason.Set.empty reasons
    in

    return (Reason.Set.elements reasons)

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

let rec findResolutionForRequest ~req = function
  | [] -> None
  | res::rest ->
    if
      Req.matches
        ~name:res.Resolver.Resolution.name
        ~version:res.Resolver.Resolution.version
        req
    then Some res
    else findResolutionForRequest ~req rest

let solutionRecordOfPkg ~solver (pkg : Package.t) =
  let open RunAsync.Syntax in

  let%bind source =
    let resolve source =
      match source with
      | Package.Source source -> return source
      | Package.SourceSpec sourceSpec ->
        Resolver.resolveSource ~name:pkg.name ~sourceSpec solver.resolver
    in
    let main, mirrors = pkg.source in
    let%bind main = resolve main and
              mirrors = RunAsync.List.joinAll (List.map ~f:resolve mirrors) in
    return (main, mirrors)
  in

  let%bind files =
    match pkg.opam with
    | Some opam -> opam.files ()
    | None -> return []
  in

  let opam =
    match pkg.opam with
    | Some opam -> Some {
        Solution.Record.Opam.
        name = opam.name;
        version = opam.version;
        opam = opam.opam;
        override =
          if Package.OpamOverride.equal opam.override Package.OpamOverride.empty
          then None
          else Some opam.override;
      }
    | None -> None
  in

  return {
    Solution.Record.
    name = pkg.name;
    version = pkg.version;
    source;
    files;
    opam;
  }

let make ~cfg ?resolver ~resolutions () =
  let open RunAsync.Syntax in
  let%bind resolver =
    match resolver with
    | None -> Resolver.make ~cfg ()
    | Some resolver -> return resolver
  in
  let universe = ref Universe.empty in
  return {cfg; resolver; universe = !universe; resolutions}

let add ~(dependencies : Dependencies.t) solver =
  let open RunAsync.Syntax in

  let universe = ref solver.universe in
  let report, finish = solver.cfg.Config.createProgressReporter ~name:"resolving esy packages" () in

  let rec addPackage (pkg : Package.t) =
    if not (Universe.mem ~pkg !universe)
    then
      match pkg.kind with
      | Package.Esy ->
        universe := Universe.add ~pkg !universe;
        let%bind dependencies = addDependencies pkg.dependencies in
        universe := (
          let pkg = {pkg with dependencies} in
          Universe.add ~pkg !universe
        );
        return ()
      | Package.Npm -> return ()
    else return ()

  and addDependencies (dependencies : Dependencies.t) =
    let dependencies =
      Dependencies.applyResolutions solver.resolutions dependencies
    in

    match dependencies with
    | Dependencies.NpmFormula reqs ->
      let%bind reqs = RunAsync.List.joinAll (
        let f (req : Req.t) = addDependency req in
        List.map ~f reqs
      ) in
      return (Dependencies.NpmFormula reqs)

    | Dependencies.OpamFormula formula ->
      let%bind rewrites =
        let f rewrites (req : Req.t) =
          let%bind nextReq = addDependency req in
          match req.spec, nextReq.Req.spec with
          | VersionSpec.Source prev, VersionSpec.Source next ->
            return (SourceSpec.Map.add prev next rewrites)
          | _ -> return rewrites
        in
        let reqs = Dependencies.toApproximateRequests dependencies in
        RunAsync.List.foldLeft ~f ~init:SourceSpec.Map.empty reqs
      in

      let formula =
        let f (dep : Package.Dep.t) =
          match dep.req with
          | Package.Dep.Source src -> begin
            match SourceSpec.Map.find_opt src rewrites with
            | Some nextSrc -> {dep with req = Package.Dep.Source nextSrc}
            | None -> dep
            end
          | _ -> dep
        in
        List.map ~f:(List.map ~f) formula
      in

      return (Dependencies.OpamFormula formula)

  and addDependency (req : Req.t) =
    let%lwt () =
      let status = Format.asprintf "%s" req.name in
      report status
    in
    let%bind resolutions, spec =
      Resolver.resolve ~fullMetadata:true ~name:req.name ~spec:req.spec solver.resolver
      |> RunAsync.withContext (Format.asprintf "resolving %a" Req.pp req)
    in

    let%bind packages =
      let fetchPackage resolution =
        Resolver.package ~resolution solver.resolver
        |> RunAsync.withContext (
            Format.asprintf "resolving metadata %a" Resolver.Resolution.pp resolution)
      in
      resolutions
      |> List.map ~f:fetchPackage
      |> RunAsync.List.joinAll
    in

    let%bind () =
      packages
      |> List.map ~f:addPackage
      |> RunAsync.List.waitAll
    in

    return (
      match spec with
      | Some spec -> Req.ofSpec ~name:req.name ~spec
      | None -> req
    )
  in

  let%bind dependencies = addDependencies dependencies in

  let%lwt () = finish () in

  (* TODO: return rewritten deps *)
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

  let runSolver filenameIn filenameOut =
    let cmd = Cmd.(
      solver.cfg.Config.esySolveCmd
      % ("--strategy=" ^ strategy)
      % ("--timeout=" ^ string_of_float(solver.cfg.solveTimeout))
      % p filenameIn
      % p filenameOut
    ) in

    let f p =
      let readAndClose ic =
        Lwt.finalize
          (fun () -> Lwt_io.read ic)
          (fun () -> Lwt_io.close ic)
      in
      let%lwt stdout = readAndClose p#stdout
          and stderr = readAndClose p#stderr in
      match%lwt p#status with
      | Unix.WEXITED 0 ->
        RunAsync.return ()
      | _ ->
        let msg =
          Format.asprintf
            "@[<v>command failed: %a@\nstderr:@[<v 2>@\n%a@]@\nstdout:@[<v 2>@\n%a@]@]"
            Cmd.pp cmd Fmt.lines stderr Fmt.lines stdout
        in
        RunAsync.error msg
    in

    let cmd = Cmd.getToolAndLine cmd in
    try%lwt
      Lwt_process.with_process_full cmd f
    with
    | Unix.Unix_error (err, _, _) ->
      let msg = Unix.error_message err in
      RunAsync.error msg
    | _ ->
      RunAsync.error "error running cudf solver"
  in

  let dummyRoot = {
    Package.
    name = "ROOT";
    version = Version.parseExn "0.0.0";
    source = Package.Source Source.NoSource, [];
    opam = None;
    dependencies;
    devDependencies = Dependencies.NpmFormula [];
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
    Fs.withTempDir (fun path ->
      let%bind filenameIn =
        let filename = Path.(path / "in.cudf") in
        let%bind () = Fs.writeFile ~data:(printCudfDoc cudf) filename in
        return filename
      in
      let filenameOut = Path.(path / "out.cudf") in
      let report, finish = solver.cfg.createProgressReporter ~name:"solving esy constraints" () in
      let%lwt () = report "running solver" in
      let%bind () = runSolver filenameIn filenameOut in
      let%lwt () = finish () in
      let%bind result =
        let%bind dataOut = Fs.readFile filenameOut in
        let dataOut = String.trim dataOut in
        if String.length dataOut = 0
        then return None
        else (
          let solution = parseCudfSolution ~cudfUniverse (dataOut ^ "\n") in
          return (Some solution)
        )
      in
      return result
    )
  in

  match%bind solution with

  | Some (_preamble, cudfUniv) ->

    let packages =
      cudfUniv
      |> Cudf.get_packages ~filter:(fun p -> p.Cudf.installed)
      |> List.map ~f:(fun p -> Universe.CudfMapping.decodePkgExn p cudfMapping)
      |> List.filter ~f:(fun p -> p.Package.name <> dummyRoot.Package.name)
      |> Package.Set.of_list
    in

    return (Ok packages)

  | None ->
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

let solveDependenciesNaively
  ~(installed : Package.Set.t)
  ~(root : Package.t)
  (dependencies : Dependencies.t)
  (solver : t) =
  let open RunAsync.Syntax in

  let report, finish = solver.cfg.Config.createProgressReporter ~name:"resolving npm packages" () in

  let installed =
    let tbl = Hashtbl.create 100 in
    Package.Set.iter (fun pkg -> Hashtbl.add tbl pkg.name pkg) installed;
    tbl
  in

  let addToInstalled pkg =
    Hashtbl.replace installed pkg.Package.name pkg
  in

  let resolveOfInstalled req =

    let rec findFirstMatching = function
      | [] -> None
      | pkg::pkgs ->
        if Req.matches
          ~name:pkg.Package.name
          ~version:pkg.Package.version
          req
        then Some pkg
        else findFirstMatching pkgs
    in

    findFirstMatching (Hashtbl.find_all installed req.name)
  in

  let resolveOfOutside req =
    let%lwt () =
      let status = Format.asprintf "%a" Req.pp req in
      report status
    in
    let%bind resolutions, _ = Resolver.resolve ~name:req.name ~spec:req.spec solver.resolver in
    match findResolutionForRequest ~req resolutions with
    | Some resolution ->
      let%bind pkg = Resolver.package ~resolution solver.resolver in
      return (Some pkg)
    | None -> return None
  in

  let resolve (req : Req.t) =
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

  let lookupDependencies, addDependencies =
    let solved = Hashtbl.create 100 in
    let key pkg = pkg.Package.name ^ "." ^ (Version.toString pkg.Package.version) in
    let lookup pkg =
      Hashtbl.find_opt solved (key pkg)
    in
    let register pkg task =
      Hashtbl.add solved (key pkg) task
    in
    lookup, register
  in

  let solveDependencies dependencies =
    let reqs =
      match dependencies with
      | Dependencies.NpmFormula reqs -> reqs
      | Dependencies.OpamFormula _ ->
        (* only use already installed dependencies here
         * TODO: refactor solution * construction so we don't need to do that *)
        let reqs = Dependencies.toApproximateRequests dependencies in
        let reqs =
          let f req = Hashtbl.mem installed req.Req.name in
          List.filter ~f reqs
        in
        reqs
    in

    let%bind pkgs =
      let f req =
        let%bind pkg =
          let context = Format.asprintf "resolving request %a" Req.pp req in
          RunAsync.withContext
            context
            (resolve req)
        in
        addToInstalled pkg;
        return pkg
      in
      reqs
      |> List.map ~f
      |> RunAsync.List.joinAll
    in
    return (Package.Set.elements (Package.Set.of_list pkgs))
  in

  let rec loop seen = function
    | pkg::rest ->
      begin match Package.Set.mem pkg seen with
      | true ->
        loop seen rest
      | false ->
        let seen = Package.Set.add pkg seen in
        let%bind dependencies =
          let context = Format.asprintf "solving dependencies of %a" Package.pp pkg in
          RunAsync.withContext
            context
            (solveDependencies pkg.dependencies)
        in
        addDependencies pkg dependencies;
        loop seen (rest @ dependencies)
      end
    | [] -> return ()
  in

  let%bind () =
    let%bind dependencies = solveDependencies dependencies in
    let%bind () = loop Package.Set.empty dependencies in
    addDependencies root dependencies;
    return ()
  in

  let%bind packagesToDependencies =
    let rec aux res = function
      | pkg::rest ->
        begin match Package.Map.find_opt pkg res with
        | Some _ -> aux res rest
        | None ->
          let deps =
            match lookupDependencies pkg with
            | Some deps -> deps
            | None -> assert false
          in
          let res =
            let deps = List.map ~f:(fun pkg -> (pkg.Package.name, pkg.Package.version)) deps in
            Package.Map.add pkg deps res
          in
          aux res (rest @ deps)
        end
      | [] -> return res
    in
    aux Package.Map.empty [root]
  in

  finish ();%lwt

  return packagesToDependencies

let solveOCamlReq ~cfg ~opamRegistry req =
  let open RunAsync.Syntax in
  let%bind resolver = Resolver.make ~opamRegistry ~cfg () in
  let%bind resolutions, _ = Resolver.resolve ~name:req.name ~spec:req.spec resolver in
  begin match findResolutionForRequest ~req resolutions with
  | Some res ->
    Logs_lwt.app (fun m -> m "using %a" Resolver.Resolution.pp res);%lwt
    return (Some res.version)
  | None ->
    Logs_lwt.warn (fun m -> m "no version found for %a" Req.pp req);%lwt
    return None
  end

let solve (sandbox : Sandbox.t) =
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

  let opamRegistry = OpamRegistry.make ~cfg:sandbox.cfg () in

  let%bind dependencies, ocamlVersion =
    match sandbox.ocamlReq with
    | None -> return (sandbox.dependencies, None)
    | Some ocamlReq ->
      let%bind ocamlVersion = solveOCamlReq ~cfg:sandbox.cfg ~opamRegistry ocamlReq in

      let dependencies =
        match ocamlVersion, sandbox.dependencies with
        | Some ocamlVersion, Package.Dependencies.NpmFormula reqs ->
          let ocamlSpec = Package.VersionSpec.ofVersion ocamlVersion in
          let ocamlReq = Req.ofSpec ~name:"ocaml" ~spec:ocamlSpec in
          let reqs = Package.NpmDependencies.override reqs [ocamlReq] in
          Package.Dependencies.NpmFormula reqs
        | Some ocamlVersion, Package.Dependencies.OpamFormula deps ->
          let req =
            match ocamlVersion with
            | Package.Version.Npm v -> Package.Dep.Npm (SemverVersion.Constraint.EQ v);
            | Package.Version.Source src -> Package.Dep.Source (Package.SourceSpec.ofSource src)
            | Package.Version.Opam v -> Package.Dep.Opam (OpamVersion.Constraint.EQ v)
          in
          let ocamlDep = {Package.Dep. name = "ocaml"; req;} in
          Package.Dependencies.OpamFormula (deps @ [[ocamlDep]])
        | None, deps -> deps
      in
      return (dependencies, ocamlVersion)
  in

  let%bind solver, dependencies =
    let%bind resolver = Resolver.make ?ocamlVersion ~opamRegistry ~cfg:sandbox.cfg () in
    let%bind solver = make ~resolver ~cfg:sandbox.cfg ~resolutions:sandbox.resolutions () in
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

  let%bind packagesToDependencies =
    solveDependenciesNaively
      ~installed
      ~root:sandbox.root
      dependencies
      solver
  in

  let%bind sol =
    let%bind sol =
      let f solution (pkg, dependencies) =
        let%bind record = solutionRecordOfPkg ~solver pkg in
        let solution = Solution.add ~record ~dependencies solution in
        return solution
      in
      packagesToDependencies
      |> Package.Map.bindings
      |> RunAsync.List.foldLeft ~f ~init:Solution.empty
    in

    let%bind record = solutionRecordOfPkg ~solver sandbox.root in
    let dependencies = Package.Map.find sandbox.root packagesToDependencies in
    return (Solution.addRoot ~record ~dependencies sol)
  in

  return sol
