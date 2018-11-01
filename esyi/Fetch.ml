module Overrides = Package.Overrides
module Package = Solution.Package
module Dist = FetchStorage.Dist

let collectPackagesOfSolution solution =
  let pkgs, root =
    let root = Solution.root solution in

    let rec collect (seen, topo) pkg =
      if Package.Set.mem pkg seen
      then seen, topo
      else
        let seen = Package.Set.add pkg seen in
        let seen, topo = collectDependencies (seen, topo) pkg in
        let topo = pkg::topo in
        seen, topo

    and collectDependencies (seen, topo) pkg =
      let isRoot = Package.compare root pkg = 0 in
      let dependencies =
        let traverse =
          if isRoot
          then Solution.traverseWithDevDependencies
          else Solution.traverse
        in
        Solution.dependencies ~traverse pkg solution
      in
      List.fold_left ~f:collect ~init:(seen, topo) dependencies
    in

    let _, topo = collectDependencies (Package.Set.empty, []) root in
    (List.rev topo), root
  in

  pkgs, root

(** This installs pnp enabled node wrapper. *)
let installNodeWrapper ~binPath ~pnpJsPath () =
  let open RunAsync.Syntax in
  match Cmd.resolveCmd System.Environment.path "node" with
  | Ok nodeCmd ->
    let%bind binPath =
      let%bind () = Fs.createDir binPath in
      return binPath
    in
    let data, path =
      match System.Platform.host with
      | Windows ->
        let data =
        Format.asprintf
          {|@ECHO off
@SETLOCAL
@SET ESY__NODE_BIN_PATH=%%%a%%
"%s" -r "%a" %%*
            |} Path.pp binPath nodeCmd Path.pp pnpJsPath
        in
        data, Path.(binPath / "node.cmd")
      | _ ->
        let data =
          Format.asprintf
            {|#!/bin/sh
export ESY__NODE_BIN_PATH="%a"
exec "%s" -r "%a" "$@"
              |} Path.pp binPath nodeCmd Path.pp pnpJsPath
        in
        data, Path.(binPath / "node")
    in
    Fs.writeFile ~perm:0o755 ~data path
  | Error _ ->
    (* no node available in $PATH, just skip this then *)
    return ()

let isInstalled ~(sandbox : Sandbox.t) (solution : Solution.t) =
  let open RunAsync.Syntax in
  let installationPath = SandboxSpec.installationPath sandbox.spec in
  match%lwt Installation.ofPath installationPath with
  | Error _
  | Ok None -> return false
  | Ok Some installation ->
    let rec check = function
      | [] -> return true
      | pkg::pkgs ->
        begin match Installation.find (Solution.Package.id pkg) installation with
        | None -> return false
        | Some path ->
          if%bind Fs.exists path
          then check pkgs
          else return false
        end
    in
    let pkgs, _root = collectPackagesOfSolution solution in
    check pkgs

let install ~report ~queue ~installation ~solution dist dependencies =
  let open RunAsync.Syntax in
  let f () =

    let id = Dist.id dist in

    let%lwt () =
      let msg = Format.asprintf "%a" PackageId.pp id in
      report msg
    in

    let onBeforeLifecycle path =
      (*
        * This creates <install>/_esy and populates it with a custom
        * per-package pnp.js (which allows to resolve dependencies out of
        * stage directory and a node wrapper which uses this pnp.js.
        *)
      let binPath = Path.(path / "_esy") in
      let%bind () = Fs.createDir binPath in

      let%bind () =
        RunAsync.List.mapAndWait
          ~f:(FetchStorage.linkBins binPath)
          dependencies
      in

      let%bind () =
        let pnpJsPath = Path.(binPath / "pnp.js") in
        let installation =
          Installation.add
            id
            (Dist.sourceStagePath dist)
            installation
        in
        let data = PnpJs.render
          ~basePath:binPath
          ~rootPath:path
          ~rootId:id
          ~solution
          ~installation
          ()
        in
        let%bind () = Fs.writeFile ~data pnpJsPath in
        installNodeWrapper
          ~binPath
          ~pnpJsPath
          ()
      in

      return ()
    in
    FetchStorage.install ~onBeforeLifecycle dist
  in
  LwtTaskQueue.submit queue f

let fetch ~(sandbox : Sandbox.t) (solution : Solution.t) =
  let open RunAsync.Syntax in

  (* Collect packages which from the solution *)
  let pkgs, root = collectPackagesOfSolution solution in

  (* Fetch all package distributions *)
  let%bind dists =
    let report, finish = Cli.createProgressReporter ~name:"fetching" () in

    let%bind dists =
      let fetch pkg =
        let%lwt () =
          let status = Format.asprintf "%a" Package.pp pkg in
          report status
        in
        FetchStorage.fetch ~sandbox pkg
      in
      RunAsync.List.mapAndJoin
        ~concurrency:40
        ~f:fetch
        pkgs
    in

    let%lwt () = finish () in

    let dists =
      let f dists dist = PackageId.Map.add (Dist.id dist) dist dists in
      List.fold_left ~f ~init:PackageId.Map.empty dists
    in

    return dists
  in

  (* Produce _esy/<sandbox>/installation.json *)
  let%bind installation =
    let installation =
      let f id dist installation =
        Installation.add id (Dist.sourceInstallPath dist) installation
      in
      let init =
        Installation.empty
        |> Installation.add
            (Package.id root)
            sandbox.spec.path;
      in
      PackageId.Map.fold f dists init
    in

    let%bind () =
      Fs.writeJsonFile
        ~json:(Installation.to_yojson installation)
        (SandboxSpec.installationPath sandbox.spec)
    in

    return installation
  in

  (* Produce _esy/<sandbox>/pnp.js *)
  let%bind () =
    let path = SandboxSpec.pnpJsPath sandbox.spec in
    let data = PnpJs.render
      ~basePath:(Path.parent (SandboxSpec.pnpJsPath sandbox.spec))
      ~rootPath:sandbox.spec.path
      ~rootId:(Solution.Package.id (Solution.root solution))
      ~solution
      ~installation
      ()
    in
    Fs.writeFile ~data path
  in

  (* place <binPath>/node executable with pnp enabled *)
  let%bind () =
    installNodeWrapper
      ~binPath:(SandboxSpec.binPath sandbox.spec)
      ~pnpJsPath:(SandboxSpec.pnpJsPath sandbox.spec)
      ()
  in

  let%bind () =

    let report, finish = Cli.createProgressReporter ~name:"installing" () in
    let queue = LwtTaskQueue.create ~concurrency:40 () in

    let tasks = Memoize.make () in

    let rec visit' seen pkg =
      let id = Package.id pkg in
      let%bind dependencies =
        RunAsync.List.mapAndJoin
          ~f:(visit seen)
          (Solution.dependencies pkg solution)
      in
      match PackageId.Map.find_opt id dists with
      | Some dist ->
        install
          ~report
          ~queue
          ~installation
          ~solution
          dist
          (List.filterNone dependencies)
      | None -> errorf "dist not found: %a" Package.pp pkg

    and visit seen pkg =
      let id = Package.id pkg in
      if not (PackageId.Set.mem id seen)
      then
        let seen = PackageId.Set.add id seen in
        let%bind installation = Memoize.compute tasks id (fun () -> visit' seen pkg) in
        return (Some installation)
      else return None
    in

    let%bind dependencies =
      RunAsync.List.mapAndJoin
        ~f:(visit PackageId.Set.empty)
        (Solution.dependencies ~traverse:Solution.traverseWithDevDependencies root solution)
    in

    let%bind () =
      let f = FetchStorage.linkBins (SandboxSpec.binPath sandbox.spec) in
      RunAsync.List.mapAndWait ~f (List.filterNone dependencies)
    in

    let%lwt () = finish () in
    return ()
  in

  return ()
