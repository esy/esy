
let run
    ?(stdin=`Null)
    ?(args=[])
    ?logPath
    ~(buildConfig : EsyBuildPackage.Config.t)
    action
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
        v "esy-build-package"
        % action
        % "--store-path" % p buildConfig.storePath
        % "--local-store-path" % p buildConfig.localStorePath
        % "--project-path" % p buildConfig.projectPath
        % "--build-path" % p buildConfig.buildPath
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
        let logPath = Scope.SandboxPath.toPath buildConfig logPath in
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
    ~buildConfig
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
  let%bind status, log = run ?logPath ~args ~buildConfig `Build plan in
  match status, log with
  | Unix.WEXITED 0, Some (_, fd)  ->
    UnixLabels.close fd;
    return ()
  | Unix.WEXITED 0, None ->
    return ()

  | Unix.WEXITED code, Some (logPath, fd)
  | Unix.WSIGNALED code, Some (logPath, fd)
  | Unix.WSTOPPED code, Some (logPath, fd) ->
    UnixLabels.close fd;
    let%bind log = Fs.readFile logPath in
    RunAsync.withContextOfLog
      ~header:"build log:" log
      (errorf "build failed with exit code: %i" code)

  | Unix.WEXITED code, None
  | Unix.WSIGNALED code, None
  | Unix.WSTOPPED code, None ->
    errorf "build failed with exit code: %i" code

let buildShell ~buildConfig plan =
  let open RunAsync.Syntax in
  let%bind status, _log = run ~stdin:`Keep ~buildConfig `Shell plan in
  return status

let buildExec ~buildConfig plan cmd =
  let open RunAsync.Syntax in
  let tool, args = Cmd.getToolAndArgs cmd in
  let args = "--"::tool::args in
  let%bind status, _log = run ~stdin:`Keep ~args ~buildConfig `Exec  plan in
  return status
