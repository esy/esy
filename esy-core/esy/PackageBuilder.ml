let esyBuildPackage =
  Cmd.resolveCmdRelativeToCurrentCmd "./esyBuildPackage.bc"

let ocamlrun =
  Cmd.resolveCmdRelativeToCurrentCmd "@esy-ocaml/ocamlrun/install/bin/ocamlrun"

let run
    ?(stdin=`Null)
    ?(stderrout=`Log)
    ?(args=[])
    action
    (cfg : Config.t)
    (task : BuildTask.t) =
  let open RunAsync.Syntax in

  let action = match action with
  | `Build -> "build"
  | `Shell -> "shell"
  | `Exec -> "exec"
  in

  let runProcess buildJsonFilename =
    let%bind command = RunAsync.liftOfRun (
      let open Run.Syntax in
      let%bind ocamlrun = ocamlrun () in
      let%bind esyBuildPackage = esyBuildPackage () in
      return Cmd.(
        ocamlrun
        %% esyBuildPackage
        % action
        % "--prefix-path" % p cfg.prefixPath
        % "--sandbox-path" % p cfg.sandboxPath
        % "--build"
        % Path.to_string buildJsonFilename
        %% (Cmd.ofList args)
      )
    ) in

    let stdin = match stdin with
    | `Null -> `Dev_null
    | `Keep -> `FD_copy Unix.stdin
    in

    let%bind stdout, stderr, log = match stderrout with
    | `Log ->
      let logPath = Config.ConfigPath.toPath cfg task.logPath in
      let fd = UnixLabels.openfile
        ~mode:Unix.[O_WRONLY; O_CREAT]
        ~perm:0o644
        (Path.to_string logPath)
      in
      return (`FD_copy fd, `FD_copy fd, Some (logPath, fd))
    | `Keep ->
      return (`FD_copy Unix.stdout, `FD_copy Unix.stderr, None)
    in

    let waitForProcess process =
      let%lwt status = process#status in
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
    in

    ChildProcess.withProcess
      ~stderr ~stdout ~stdin
      command waitForProcess
  in

  let buildJson = BuildTask.toBuildProtocolString task in
  Fs.withTemporaryFile buildJson runProcess

let build
    ?(force=false)
    ?(buildOnly=false)
    ?(quiet=false)
    ?(stderrout : [`Keep | `Log] option)
    =
  let args =
    let addIf cond arg args =
      if cond then arg::args else args
    in
    []
    |> addIf force "--force"
    |> addIf buildOnly "--build-only"
    |> addIf quiet "--quiet"
  in
  run ~args ?stderrout `Build

let buildShell =
  run ~stdin:`Keep ~stderrout:`Keep `Shell

let buildExec cfg task command =
  let args = "--"::command in
  run ~stdin:`Keep ~stderrout:`Keep `Exec ~args cfg task
