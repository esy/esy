let runPatch cmd =
  let f p =
    let%lwt stdout = Lwt_io.read p#stdout
    and stderr = Lwt_io.read p#stderr in
    match%lwt p#status with
    | Unix.WEXITED 0 ->
      RunAsync.return ()
    | _ ->
      let%lwt () =
        Logs_lwt.err (fun m -> m
          "@[<v>command failed: %a@\nstderr:@[<v 2>@\n%a@]@\nstdout:@[<v 2>@\n%a@]@]"
          Cmd.pp cmd Fmt.lines stderr Fmt.lines stdout
        )
      in
      RunAsync.error "error running command"
  in
  try%lwt
    EsyBashLwt.with_process_full cmd f
  with
  | Unix.Unix_error (err, _, _) ->
    let msg = Unix.error_message err in
    RunAsync.error msg
  | _ ->
    RunAsync.error "error running subprocess"

let apply ~strip ~root ~patch () =
  let cmd = Cmd.(
    v "patch"
    % "--directory" % p root
    % "--strip" % string_of_int strip
    % "--input" % p patch
  ) in
  runPatch cmd
