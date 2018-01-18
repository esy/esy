
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

    let command =
      let prg = "./_build/default/esy-build-package/esyBuildPackage.bc" in
      let args = Array.of_list (
        [prg; action; "--build"; (Path.to_string buildJsonFilename)]
        @ args
      ) in
      (prg, args)
    in

    let%lwt () =
      let buildJsonData =
        task
        |> BuildTask.ExternalFormat.ofBuildTask
        |> BuildTask.ExternalFormat.toString
        in
      Lwt_io.write buildJsonOc buildJsonData
    in

    let f process =
      match%lwt process#status with
      | Unix.WEXITED 0 -> return ()
      | _ -> error "build process exited with an error"
    in
    let stdin = match stdin with
    | `Null -> `Dev_null
    | `Keep -> `FD_copy Unix.stdin
    in
    let%bind stdout, stderr = match stderrout with
    | `Log ->
      let logPath = task.logPath |> Config.ConfigPath.toPath cfg |> Path.to_string in
      let fd = UnixLabels.openfile ~mode:Unix.[O_WRONLY; O_CREAT] ~perm:0o644 logPath in
      return (`FD_copy fd, `FD_copy fd)
    | `Keep ->
      return (`FD_copy Unix.stdout, `FD_copy Unix.stderr)
    in
    try%lwt
      Lwt_process.with_process_none ~stderr ~stdout ~stdin command f
    with
    | Unix.Unix_error (err, _, _) ->
      let msg = Unix.error_message err in
      error msg
    | _ -> error "some error"
  in Io.withTemporaryFile runProcess

let build ?(force=false) ?stderrout =
  let args = if force then ["--force"] else [] in
  run ~args ?stderrout `Build

let buildShell =
  run ~stdin:`Keep ~stderrout:`Keep `Shell

let buildExec cfg task command =
  let args = "--"::command in
  run ~stdin:`Keep ~stderrout:`Keep `Exec ~args cfg task
