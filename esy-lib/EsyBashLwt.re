let toRunAsyncCommand = cmd => {
  let resolvedCommand = EsyBash.toEsyBashCommand(Cmd.toBosCmd(cmd));
  switch (resolvedCommand) {
  | Ok(v) => RunAsync.return(Cmd.ofBosCmd(v))
  | Error(`Msg(line)) => RunAsync.error(line)
  | _ => RunAsync.error("unknown error")
  };
};

let getMingwRuntimePath = () => {
  let runtimePath = EsyBash.getMingwRuntimePath();
  switch (runtimePath) {
  | Ok(v) => RunAsync.return(v)
  | _ => RunAsync.error("Error locating mingw runtime path.")
  };
};

let getMingwEnvironmentOverride = () =>
  RunAsync.Syntax.(
    switch (System.Platform.host) {
    | Windows =>
      let currentPath = Sys.getenv("PATH");
      let%bind mingwRuntime = getMingwRuntimePath();
      return(
        ChildProcess.CurrentEnvOverride(
          Astring.String.Map.(
            add(
              "PATH",
              Fpath.to_string(mingwRuntime) ++ ";" ++ currentPath,
              empty,
            )
          ),
        ),
      );
    | _ => return(ChildProcess.CurrentEnv)
    }
  );

/**
 * Helper utility to run a command with 'esy-bash', via Lwt.
 * This is meant to replace Lwt's with_process_full in the case
 * of executing bash commands */
let with_process_full = (~env=?, cmd, f) =>
  RunAsync.Syntax.(
    {
      let%bind res = toRunAsyncCommand(cmd);
      switch (res) {
      | Ok(v) =>
        let tl = Cmd.getToolAndLine(v);
        switch env {
        | Some(env) => Lwt_process.with_process_full(~env, tl, f);
        | None => Lwt_process.with_process_full(tl, f);
        }
      | _ => RunAsync.error("error running command: " ++ Cmd.show(cmd))
      };
    }
  );
