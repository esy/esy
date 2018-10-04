
let run
    ?(stdin=`Null)
    ?(args=[])
    ?logPath
    action
    (sandbox : Sandbox.t)
    (plan : EsyBuildPackage.Plan.t) =
  let open RunAsync.Syntax in

  let action = match action with
  | `Build -> "build"
  | `Shell -> "shell"
  | `Exec -> "exec"
  in

  let runProcess buildJsonFilename =
    let%bind command = RunAsync.ofRun (
      let open Run.Syntax in
      return Cmd.(
        sandbox.cfg.esyBuildPackageCommand
        % action
        % "--store-path" % p sandbox.buildConfig.storePath
        % "--local-store-path" % p sandbox.buildConfig.localStorePath
        % "--project-path" % p sandbox.buildConfig.projectPath
        % "--build-path" % p sandbox.buildConfig.buildPath
        % "--plan" % p buildJsonFilename
        |> addArgs args
      )
    ) in

    let stdin = match stdin with
    | `Null -> `Dev_null
    | `Keep -> `FD_copy Unix.stdin
    in

    let%bind stdout, stderr, log =
      match logPath with
      | Some logPath ->
        let logPath = Sandbox.Path.toPath sandbox.buildConfig logPath in
        let%lwt fd = Lwt_unix.openfile
          (Path.show logPath)
          Lwt_unix.[O_WRONLY; O_CREAT]
          0o644
        in
        let fd = Lwt_unix.unix_file_descr fd in
        return (`FD_copy fd, `FD_copy fd, Some (logPath, fd))
      | None ->
        return (`FD_copy Unix.stdout, `FD_copy Unix.stderr, None)
    in

    let waitForProcess process =
      let%lwt status = process#status in
      return (status, log)
    in

    ChildProcess.withProcess
      ~stderr ~stdout ~stdin
      command waitForProcess
  in

  let buildJson =
    let json = EsyBuildPackage.Plan.to_yojson plan in
    Yojson.Safe.to_string json
  in
  Fs.withTempFile ~data:buildJson runProcess

let build
    ?(force=false)
    ?(buildOnly=false)
    ?(quiet=false)
    ?logPath
    sandbox
    plan
    =
  let open RunAsync.Syntax in
  let args =
    let addIf cond arg args =
      if cond then arg::args else args
    in
    []
    |> addIf force "--force"
    |> addIf buildOnly "--build-only"
    |> addIf quiet "--quiet"
  in
  let%bind status, log = run ?logPath ~args `Build sandbox plan in
  match status, log with
  | Unix.WEXITED 0, Some (_, fd)  ->
    UnixLabels.close fd;
    return ()
  | Unix.WEXITED 0, None ->
    return ()
  | _, Some (logPath, fd) ->
    UnixLabels.close fd;
    let%bind log = Fs.readFile logPath in
    RunAsync.withContextOfLog ~header:"build log:" log (error "build failed")
  | _, None ->
    error "build failed"

let buildShell sandbox plan =
  let open RunAsync.Syntax in
  let%bind status, _log = run ~stdin:`Keep `Shell sandbox plan in
  return status

let buildExec sandbox plan cmd =
  let open RunAsync.Syntax in
  let tool, args = Cmd.getToolAndArgs cmd in
  let args = "--"::tool::args in
  let%bind status, _log = run ~stdin:`Keep `Exec ~args sandbox plan in
  return status
