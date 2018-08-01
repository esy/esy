let toRunAsyncCommand = (cmd) => {
    let resolvedCommand = EsyBash.toEsyBashCommand(Cmd.toBosCmd(cmd));
    switch (resolvedCommand) {
    | Ok(v) => 
        print_endline("toRunAsyncCommand: " ++ Bos.Cmd.to_string(v));
        RunAsync.return(Cmd.ofBosCmd(v))
    | Error(`Msg(line)) => RunAsync.error(line)
    | _ => RunAsync.error("unknown error")
    };
};

let getToolAndLine = (cmd) => {
    let (tool, line) = Cmd.getToolAndLine(cmd);

    switch (System.Platform.host) {
    | System.Platform.Windows => ("", line)
    | _ => (tool, line)
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
        let tl = getToolAndLine(v);
        let result = Lwt_process.with_process_full(tl, f);
        print_endline ("Command succeeded");
        result;
    | _ => RunAsync.error("error running command: " ++ Cmd.toString(cmd))
    };
};

let with_process_in = (~env=?, ~stdin=?, ~stderr=?, cmd: Cmd.t, f) => {
    open RunAsync.Syntax;
    let%bind res = toRunAsyncCommand(cmd);
    switch (res) {
    | Ok(v) =>
        print_endline ("with_process_in: " ++ Cmd.toString(cmd));
        let tl = getToolAndLine(v);
         Lwt_process.with_process_in(~env?, ~stdin?, ~stderr?, tl, f);
    | _ => RunAsync.error("error running")
    };
};

let run = (cmd) => {
   open RunAsync.Syntax; 

   let f = (process) => {
       switch%lwt (process#status) {
        | Unix.WEXITED(0) => return ()
        | _ =>
            let cmd = Cmd.toString(cmd);
            let msg = Printf.sprintf("error running command: %s", cmd);
            error(msg);
        };
   };

   with_process_full(cmd, f);
}
