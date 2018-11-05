let toRunAsyncCommand = cmd =>
  switch (Cmd.ofBosCmd(EsyBash.toEsyBashCommand(Cmd.toBosCmd(cmd)))) {
  | Ok(cmd) => cmd
  | Error(`Msg(msg)) =>
    /* We just fail here assuming `EsyBash.toEsyBashCommand behave correctly.
     * Otherwise we can't recover. */
    Exn.fail(msg)
  };

/**
 * Helper utility to run a command with 'esy-bash', via Lwt.
 * This is meant to replace Lwt's with_process_full in the case
 * of executing bash commands */
let with_process_full = (~env=?, cmd, f) => {
  let cmd = toRunAsyncCommand(cmd);
  let tl = Cmd.getToolAndLine(cmd);
  Lwt_process.with_process_full(~env?, tl, f);
};
