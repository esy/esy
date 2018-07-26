
let run
    ?(stdin=`Null)
    ?(stderrout=`Log)
    ?(args=[])
    action
    (cfg : Config.t)
    (task : Task.t) =
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
        cfg.esyBuildPackageCommand
        % action
        % "--prefix-path" % p cfg.prefixPath
        % "--sandbox-path" % p cfg.sandboxPath
        % "--build"
        % Path.to_string buildJsonFilename
        |> addArgs args
      )
    ) in

    let stdin = match stdin with
    | `Null -> `Dev_null
    | `Keep -> `FD_copy Unix.stdin
    in

    let%bind stdout, stderr, log = match stderrout with
    | `Log ->
      let logPath = Config.Path.toPath cfg task.paths.logPath in
      let%lwt fd = Lwt_unix.openfile
        (Path.to_string logPath)
        Lwt_unix.[O_WRONLY; O_CREAT]
        0o644
      in
      let fd = Lwt_unix.unix_file_descr fd in
      return (`FD_copy fd, `FD_copy fd, Some (logPath, fd))
    | `Keep ->
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

  let buildJson = Task.toBuildProtocolString task in
  Fs.withTempFile ~data:buildJson runProcess

let build
    ?(force=false)
    ?(buildOnly=false)
    ?(quiet=false)
    ?(stderrout : [`Keep | `Log] option)
    cfg
    task
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
  let%bind status, log = run ~args ?stderrout `Build cfg task in
  match status, log with
  | Unix.WEXITED 0, Some (_, fd)  ->
    UnixLabels.close fd;
    return ()
  | Unix.WEXITED 0, None ->
    return ()
  | _, Some (logPath, fd) ->
    UnixLabels.close fd;
    let%bind log = Fs.readFile logPath in
    RunAsync.withContextOfLog ~header:"Build log:" log (error "build failed")
  | _, None ->
    error "build failed"

let buildShell cfg task =
  let open RunAsync.Syntax in
  let%bind status, _log = run ~stdin:`Keep ~stderrout:`Keep `Shell cfg task in
  return status

let buildExec cfg task cmd =
  let open RunAsync.Syntax in
  let tool, args = Cmd.getToolAndArgs cmd in
  let args = "--"::tool::args in
  let%bind status, _log = run ~stdin:`Keep ~stderrout:`Keep `Exec ~args cfg task in
  return status
