
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

  let runProcess buildJsonFilename buildJsonOc =
    let%bind command =
      let%bind path = RunAsync.liftOfRun (Run.liftOfBosError(
        let open Std.Result in
        let%bind currentFilename = Path.of_string (Sys.argv.(0)) in
        let currentDirname = Path.parent currentFilename in
        let path = Path.(
          currentDirname
          / ".."
          / ".."
          / "esy-build-package"
          / "bin"
          / "esyBuildPackageCommand.bc"
        ) in Ok path
      )) in
      if%bind Io.exists path then
        let prg = Path.to_string path in
        let args = Array.of_list (
          [prg; action; "--build"; (Path.to_string buildJsonFilename)]
          @ args
        ) in
        return (prg, args)
      else
        error "unable to resolve esy-build-package command"
    in

    let%lwt () =
      let buildJsonData = BuildTask.toBuildProtocolString task in
      Lwt_io.write buildJsonOc buildJsonData
    in

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
        let%bind log = Io.readFile logPath in
        RunAsync.withContextOfLog ~header:"Build log:" log (error "build failed")
      | _, None ->
        error "build failed"
    in

    try%lwt
      Lwt_process.with_process_none
        ~stderr ~stdout ~stdin
        command waitForProcess
    with
    | Unix.Unix_error (err, _, _) ->
      let msg = Unix.error_message err in
      error msg
    | _ -> error "some error"
  in Io.withTemporaryFile runProcess

let build ?(force=false) ?(buildOnly=false) ?stderrout =
  let args =
    let addIf cond arg args =
      if cond then arg::args else args
    in
    []
    |> addIf force "--force"
    |> addIf buildOnly "--build-only"
  in
  run ~args ?stderrout `Build

let buildShell =
  run ~stdin:`Keep ~stderrout:`Keep `Shell

let buildExec cfg task command =
  let args = "--"::command in
  run ~stdin:`Keep ~stderrout:`Keep `Exec ~args cfg task
