let cmd =
  let open Result.Syntax in
  (* TODO: this is too specific for a library function. *)
  let req = "../esy-build-package/bin/esyRewritePrefixCommand.exe" in
  let%bind cmd = NodeResolution.resolve req in
  return (Cmd.ofPath cmd)

let rewritePrefix ~origPrefix ~destPrefix path =
  let%lwt () = Logs_lwt.debug (fun m ->
    m "rewritePrefix %a: %a -> %a"
    Path.pp path
    Path.pp origPrefix
    Path.pp destPrefix
  ) in
  let env = EsyBash.currentEnvWithMingwInPath in
  match cmd with
  | Ok cmd ->
    ChildProcess.run ~env:(ChildProcess.CustomEnv env) Cmd.(
      cmd
      % "--orig-prefix" % p origPrefix
      % "--dest-prefix" % p destPrefix
      % p path
    )
  | Error (`Msg msg) -> Exn.failf "error: invalid esy installation: %s" msg
