let resolveCommand req =
  let cache = ref None in

  let resolver () =
    Run.liftOfBosError(
      match !cache with
      | Some path -> path
      | None ->
        let open Std.Result in
        let%bind currentFilename = Path.of_string (Sys.argv.(0)) in
        let currentDirname = Path.parent currentFilename in
        let path =
          match EsyBuildPackage.NodeResolution.resolve req currentDirname with
          | Ok (Some path) -> Ok (Path.to_string path)
          | Ok None -> Error (`Msg ("unable to resolve " ^ req))
          | Error err -> Error err
        in
        cache := Some path;
        path
    )

  in resolver

let esyBuildPackage =
  resolveCommand "./esyBuildPackage.bc"

let ocamlrun =
  resolveCommand "@esy-ocaml/ocamlrun/install/bin/ocamlrun"

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
    let%bind command = RunAsync.liftOfRun (
      let open Run.Syntax in
      let%bind ocamlrun = ocamlrun () in
      let%bind esyBuildPackage = esyBuildPackage () in
      let args = Array.of_list (
        [ocamlrun; esyBuildPackage; action; "--build"; (Path.to_string buildJsonFilename)]
        @ args
      ) in
      return (ocamlrun, args)
    ) in

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
