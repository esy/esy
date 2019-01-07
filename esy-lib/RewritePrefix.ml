let cmd =
  (* TODO: this is too specific for a library function. *)
  let req = "../../esy-build-package/bin/esyRewritePrefixCommand.exe" in
  match NodeResolution.resolve req with
  | Ok cmd -> Cmd.ofPath cmd
  | Error (`Msg msg) -> failwith msg

let rewritePrefix ~origPrefix ~destPrefix path =
  let%lwt () = Logs_lwt.debug (fun m ->
    m "rewritePrefix %a: %a -> %a"
    Path.pp path
    Path.pp origPrefix
    Path.pp destPrefix
  ) in
  let env = EsyBash.currentEnvWithMingwInPath in
  ChildProcess.run ~env:(ChildProcess.CustomEnv env) Cmd.(
    cmd
    % "--orig-prefix" % p origPrefix
    % "--dest-prefix" % p destPrefix
    % p path
  )
