module Overrides = Package.Overrides
module Package = Solution.Package
module Dist = FetchStorage.Dist

let nodeCmd =
  Cmd.resolveCmd System.Environment.path "node"

module PackageJson = struct

  module Scripts = struct
    type t = {
      postinstall : (string option [@default None]);
      install : (string option [@default None]);
    }
    [@@deriving of_yojson { strict = false }]

    let empty = {postinstall = None; install = None}
  end

  module Bin = struct
    type t =
      | Empty
      | One of string
      | Many of string StringMap.t

    let of_yojson =
      let open Result.Syntax in
      function
      | `String cmd ->
        let cmd = String.trim cmd in
        begin match cmd with
        | "" -> return Empty
        | cmd -> return (One cmd)
        end
      | `Assoc items ->
        let%bind items =
          let f cmds (name, json) =
            match json with
            | `String cmd -> return (StringMap.add name cmd cmds)
            | _ -> error "expected a string"
          in
          Result.List.foldLeft ~f ~init:StringMap.empty items
        in
        return (Many items)
      | _ -> error "expected a string or an object"
  end

  type t = {
    name : string option [@default None];
    bin : (Bin.t [@default Bin.Empty]);
    scripts : (Scripts.t [@default Scripts.empty]);
    esy : (Json.t option [@default None]);
  } [@@deriving of_yojson { strict = false }]

  let ofDir path =
    let open RunAsync.Syntax in
    let filename = Path.(path / "package.json") in
    if%bind Fs.exists filename
    then
      let%bind json = Fs.readJsonFile filename in
      let%bind manifest = RunAsync.ofRun (Json.parseJsonWith of_yojson json) in
      return (Some manifest)
    else
      return None

  let packageCommands (sourcePath : Path.t) manifest =
    let makePathToCmd cmdPath = Path.(sourcePath // v cmdPath |> normalize) in
    match manifest.bin, manifest.name with
    | Bin.One cmd, Some name ->
      [name, makePathToCmd cmd]
    | Bin.One cmd, None ->
      let cmd = makePathToCmd cmd in
      let name = Path.basename cmd in
      [name, cmd]
    | Bin.Many cmds, _ ->
      let f name cmd cmds = (name, makePathToCmd cmd)::cmds in
      (StringMap.fold f cmds [])
    | Bin.Empty, _ -> []

end

module Install = struct

  type t = {
    path : Path.t;
    sourcePath : Path.t;
    pkg : Package.t;
    isDirectDependencyOfRoot : bool;
    status: FetchStorage.status;
  }

  let pp fmt installation =
    Fmt.pf fmt "%a at %a"
      Package.pp installation.pkg
      Path.pp installation.path
end

let runLifecycleScript ?env ~install ~lifecycleName script =
  let%lwt () = Logs_lwt.debug
    (fun m ->
      m "Fetch.runLifecycleScript ~env:%a ~pkg:%a ~lifecycleName:%s"
      (Fmt.option ChildProcess.pp_env) env
      Package.pp install.Install.pkg
      lifecycleName
    )
  in

  let%lwt () = Logs_lwt.app
    (fun m ->
      m "%a: running %a lifecycle"
      Package.pp install.Install.pkg
      Fmt.(styled `Bold string) lifecycleName
    )
  in

  let readAndCloseChan ic =
    Lwt.finalize
      (fun () -> Lwt_io.read ic)
      (fun () -> Lwt_io.close ic)
  in

  let f p =
    let%lwt stdout = readAndCloseChan p#stdout
    and stderr = readAndCloseChan p#stderr in
    match%lwt p#status with
    | Unix.WEXITED 0 ->
      RunAsync.return ()
    | _ ->
      Logs_lwt.err (fun m -> m
        "@[<v>command failed: %s@\nstderr:@[<v 2>@\n%s@]@\nstdout:@[<v 2>@\n%s@]@]"
        script stderr stdout
      );%lwt
      RunAsync.error "error running command"
  in

  try%lwt
    (* We don't need to wrap the install path on Windows in quotes *)
    let installationPath =
      match System.Platform.host with
      | Windows -> Path.show install.path
      | _ -> Filename.quote (Path.show install.path)
    in
    let script =
      Printf.sprintf
        "cd %s && %s"
        installationPath
        script
    in
    let cmd =
      match System.Platform.host with
      | Windows -> ("", [|"cmd.exe";("/c " ^ script)|])
      | _ -> ("/bin/bash", [|"/bin/bash";"-c";script|])
    in
    let env =
      let open Option.Syntax in
      let%bind env = env in
      let%bind _, env = ChildProcess.prepareEnv env in
      return env
    in
    Lwt_process.with_process_full ?env cmd f
  with
  | Unix.Unix_error (err, _, _) ->
    let msg = Unix.error_message err in
    RunAsync.error msg
  | _ ->
    RunAsync.error "error running subprocess"

let runLifecycle ?env ~install ~(pkgJson : PackageJson.t) () =
  let open RunAsync.Syntax in
  let%bind () =
    match pkgJson.scripts.install with
    | Some cmd -> runLifecycleScript ?env ~install ~lifecycleName:"install" cmd
    | None -> return ()
  in
  let%bind () =
    match pkgJson.scripts.postinstall with
    | Some cmd -> runLifecycleScript ?env ~install ~lifecycleName:"postinstall" cmd
    | None -> return ()
  in
  return ()

let isInstalled ~(sandbox : Sandbox.t) (solution : Solution.t) =
  let open RunAsync.Syntax in
  let installationPath = SandboxSpec.installationPath sandbox.spec in
  match%lwt Installation.ofPath installationPath with
  | Error _
  | Ok None -> return false
  | Ok Some installation ->
    let f pkg _deps isInstalled =
      if%bind isInstalled
      then
        match Installation.find (Solution.Package.id pkg) installation with
        | Some path -> Fs.exists path
        | None -> return false
      else
        return false
    in
    Solution.fold ~f ~init:(return true) solution

let installBinWrapper ~binPath (name, origPath) =
  let open RunAsync.Syntax in
  Logs_lwt.debug (fun m ->
    m "Fetch:installBinWrapper: %a / %s -> %a"
    Path.pp origPath name Path.pp binPath
  );%lwt
  if%bind Fs.exists origPath
  then (
    let%bind () = Fs.chmod 0o777 origPath in
    Fs.symlink ~src:origPath Path.(binPath / name)
  ) else (
    Logs_lwt.warn (fun m -> m "missing %a defined as binary" Path.pp origPath);%lwt
    return ()
  )

let fetch ~(sandbox : Sandbox.t) (solution : Solution.t) =
  let open RunAsync.Syntax in

  (* Collect packages which from the solution *)
  let nodeModulesPath = SandboxSpec.nodeModulesPath sandbox.spec in

  let%bind () = Fs.rmPath nodeModulesPath in
  let%bind () = Fs.createDir nodeModulesPath in

  let%bind pkgs, root =
    let root = Solution.root solution in
    let all =
      let f pkg _ pkgs = Package.Set.add pkg pkgs in
      Solution.fold ~f ~init:Package.Set.empty solution
    in
    return (Package.Set.remove root all, root)
  in

  let directDependenciesOfRoot =
    let deps = Solution.dependencies root solution in
    Package.Set.of_list deps
  in

  (* Fetch all package distributions *)
  let%bind dists =
    let queue = LwtTaskQueue.create ~concurrency:8 () in
    let report, finish = Cli.createProgressReporter ~name:"fetching" () in

    let%bind dists =
      let fetch pkg () =
        let%lwt () =
          let status = Format.asprintf "%a" Package.pp pkg in
          report status
        in
        let%bind dist = FetchStorage.fetch ~sandbox pkg in
        let%bind status, path = FetchStorage.install ~sandbox dist in
        Logs_lwt.debug (fun m ->
          m "fetched: %a -> %a" Package.pp pkg Path.pp path);%lwt
        let%bind pkgJson = PackageJson.ofDir path in
        let install = {
          Install.
          pkg;
          sourcePath = path;
          path;
          isDirectDependencyOfRoot = Package.Set.mem pkg directDependenciesOfRoot;
          status;
        } in
        let id = Dist.id dist in
        return (id, (dist, install, pkgJson))
      in
      pkgs
      |> Package.Set.elements
      |> List.map ~f:(fun pkg -> LwtTaskQueue.submit queue (fetch pkg))
      |> RunAsync.List.joinAll
    in
    let%lwt () = finish () in

    let dists =
      let f dists (id, v) = PackageId.Map.add id v dists in
      List.fold_left ~f ~init:PackageId.Map.empty dists
    in

    return dists
  in

  (* Produce _esy/<sandbox>/installation.json *)
  let%bind installation =
    let installation =
      let f id (dist, install, _pkgJson) installation =
        let loc =
          let source = Dist.source dist in
          match source with
          | Source.LocalPathLink {path; manifest = _} -> Path.(sandbox.spec.path // path)
          | _ -> install.Install.sourcePath;
        in
        Installation.add id loc installation
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
    let data = PnpJs.render ~solution ~installation ~sandbox:sandbox.spec () in
    Fs.writeFile ~data path
  in

  (* Run lifecycle scripts *)
  let%bind () =

    let queue = LwtTaskQueue.create ~concurrency:8 () in

    let%bind binPath =
      let binPath = SandboxSpec.binPath sandbox.spec in
      let%bind () = Fs.createDir binPath in
      return binPath
    in

    (* place <binPath>/node executable with pnp enabled *)
    let%bind () =
      match nodeCmd with
      | Ok nodeCmd ->
        let pnpJs = SandboxSpec.pnpJsPath sandbox.spec in
        let data =
          Printf.sprintf
            {|#!/bin/sh
            exec %s -r "%s" "$@"
             |} nodeCmd (Path.show pnpJs)
        in
        Fs.writeFile ~perm:0o755 ~data Path.(binPath / "node")
      | Error _ ->
        (* no node available in $PATH, just skip this then *)
        return ()
    in

    let env =
      let override =
        let path = (Path.show binPath)::System.Environment.path in
        let sep = System.Environment.sep ~name:"PATH" () in
        Astring.String.Map.(
          empty
          |> add "PATH" (String.concat sep path)
        )
      in
      ChildProcess.CurrentEnvOverride override
    in

    let process install pkgJson =
      let%bind () =
        Logs_lwt.debug (fun m -> m "Fetch:runLifecycle:%a" Package.pp install.Install.pkg);%lwt
        RunAsync.contextf
          (LwtTaskQueue.submit
            queue
            (runLifecycle
              ~env
              ~install
              ~pkgJson))
          "running lifecycle %a"
          Install.pp install

      in

      let%bind () =
        Logs_lwt.debug (fun m -> m "Fetch:installBinWrappers:%a" Package.pp install.Install.pkg);%lwt
        PackageJson.packageCommands install.Install.sourcePath pkgJson
        |> List.map ~f:(installBinWrapper ~binPath)
        |> RunAsync.List.waitAll
      in

      return ()
    in

    let seen = ref Package.Set.empty in

    let rec visit pkg =
      if Package.Set.mem pkg !seen
      then return ()
      else (
        seen := Package.Set.add pkg !seen;
        let isRoot = Package.compare root pkg = 0 in
        let dependendencies =
          let traverse =
            if isRoot
            then Solution.traverseWithDevDependencies
            else Solution.traverse
          in
          Solution.dependencies ~traverse pkg solution
        in
        let%bind () =
          List.map ~f:visit dependendencies
          |> RunAsync.List.waitAll
        in

        match isRoot, PackageId.Map.find_opt (Solution.Package.id pkg) dists with
        | false, Some (
            _dist,
            ({Install. status = FetchStorage.Fresh; _ } as install),
            Some ({PackageJson. esy = None; _} as pkgJson)
          ) ->
          process install pkgJson
        | false, Some (_, {status = FetchStorage.Cached;_}, _) -> return ()
        | false, Some (_, {status = FetchStorage.Fresh;_}, _) -> return ()
        | false, None -> errorf "dist not found: %a" Package.pp pkg
        | true, _ -> return ()
      )
    in

    visit root
  in

  (* Produce _esy/<sandbox>/bin *)
  let%bind () =
    let path = SandboxSpec.pnpJsPath sandbox.spec in
    let data = PnpJs.render ~solution ~installation ~sandbox:sandbox.spec () in
    Fs.writeFile ~data path
  in

  return ()
