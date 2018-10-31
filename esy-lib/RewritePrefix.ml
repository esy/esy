let cmd = ref None

let rewritePrefix ~origPrefix ~destPrefix path =
  Logs_lwt.debug (fun m ->
    m "rewritePrefix %a: %a -> %a"
    Path.pp path
    Path.pp origPrefix
    Path.pp destPrefix
  );%lwt
  let cmd =
    match !cmd with
    | Some cmd -> cmd
    | None -> failwith "esy-rewrite-prefix command isn't configured"
  in
  ChildProcess.run Cmd.(
    cmd
    % "--orig-prefix" % p origPrefix
    % "--dest-prefix" % p destPrefix
    % p path
  )
