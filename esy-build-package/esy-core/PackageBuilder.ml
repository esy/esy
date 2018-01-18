let run ?(stdin=`Null) action (task : BuildTask.t) =
  let open RunAsync.Syntax in

  let action = match action with
  | `Build -> "build"
  | `Shell -> "shell"
  | `Exec -> "exec"
  in

  let runProcess buildJsonFilename buildJsonOc =

    let command =
      let prg = "./_build/default/esy-build-package/esyBuildPackage.bc" in let args = [|
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
    try%lwt
      Lwt_process.with_process_none
        ~stderr:(`FD_copy Unix.stderr)
        ~stdout:(`FD_copy Unix.stdout)
        ~stdin
        command f
    with
    | _ -> error "some error"
  in Io.withTemporaryFile runProcess

let build = run `Build
let buildShell = run ~stdin:`Keep `Shell
let buildExec = run ~stdin:`Keep `Exec
