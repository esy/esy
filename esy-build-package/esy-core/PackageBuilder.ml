
let run
    ?(stdin=`Null)
    ?(stderrout=`Log)
    action
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
      let args = [|
        prg;
        action;
        "--build"; (Path.to_string buildJsonFilename);
      |] in
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
    let stdout, stderr = match stderrout with
    | `Log ->
      `FD_copy Unix.stdout, `FD_copy Unix.stderr
    | `Keep -> `FD_copy Unix.stdout, `FD_copy Unix.stderr
    in
    try%lwt
      Lwt_process.with_process_none ~stderr ~stdout ~stdin command f
    with
    | _ -> error "some error"
  in Io.withTemporaryFile runProcess

let build = run `Build
let buildShell = run ~stdin:`Keep `Shell
let buildExec = run ~stdin:`Keep `Exec
