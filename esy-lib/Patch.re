let runPatch = cmd => {
  let f = p => {
    let%lwt stdout = Lwt_io.read(p#stdout)
    and stderr = Lwt_io.read(p#stderr);
    switch%lwt (p#status) {
    | Unix.WEXITED(0) => RunAsync.return()
    | _ =>
      let%lwt () =
        Esy_logs_lwt.err(m =>
          m(
            "@[<v>command failed: %a@\nstderr:@[<v 2>@\n%a@]@\nstdout:@[<v 2>@\n%a@]@]",
            Cmd.pp,
            cmd,
            Fmt.lines,
            stderr,
            Fmt.lines,
            stdout,
          )
        );

      RunAsync.error("error running command");
    };
  };

  try%lwt(EsyBashLwt.with_process_full(cmd, f)) {
  | [@implicit_arity] Unix.Unix_error(err, _, _) =>
    let msg = Unix.error_message(err);
    RunAsync.error(msg);
  | _ => RunAsync.error("error running subprocess")
  };
};

let apply = (~strip, ~root, ~patch, ()) => {
  let cmd =
    Cmd.(
      v("patch")
      % "--directory"
      % p(root)
      % "--strip"
      % string_of_int(strip)
      % "--input"
      % p(patch)
    );
  runPatch(cmd);
};
