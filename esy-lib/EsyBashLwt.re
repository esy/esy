let toRunAsyncCommand = (cmd) => {
    let resolvedCommand = EsyBash.toEsyBashCommand(Cmd.toBosCmd(cmd));
    switch (resolvedCommand) {
    | Ok(v) => RunAsync.return(Cmd.ofBosCmd(v))
    | Error(`Msg(line)) => RunAsync.error(line)
    | _ => RunAsync.error("unknown error")
    };
};

/**
 * Helper utility to run a command with 'esy-bash', via Lwt.
 * This is meant to replace Lwt's with_process_full in the case
 * of executing bash commands */
let with_process_full = (cmd, f) => {
    open RunAsync.Syntax;
    let%bind res = toRunAsyncCommand(cmd);
    switch (res) {
    | Ok(v) =>
        let tl = Cmd.getToolAndLine(v);
        Lwt_process.with_process_full(tl, f);
    | _ => RunAsync.error("error running command: " ++ Cmd.toString(cmd))
    };
};
