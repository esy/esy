type env =
  /* Use current env */
  | CurrentEnv
  /* Use current env add some override on top */
  | CurrentEnvOverride(StringMap.t(string))
  /* Use custom env */
  | CustomEnv(StringMap.t(string));

let pp_env = (fmt, env) =>
  switch (env) {
  | CurrentEnv => Fmt.any("CurrentEnv", fmt, ())
  | CurrentEnvOverride(env) =>
    Fmt.pf(
      fmt,
      "CustomEnvOverride %a",
      Astring.String.Map.pp(Fmt.(pair(string, string))),
      env,
    )
  | CustomEnv(env) =>
    Fmt.pf(
      fmt,
      "CustomEnv %a",
      Astring.String.Map.pp(Fmt.(pair(string, string))),
      env,
    )
  };

let resolveCmdInEnv = (~env, prg) => {
  let path = {
    let v =
      switch (StringMap.find_opt("PATH", env)) {
      | Some(v) => v
      | None => ""
      };

    String.split_on_char(System.Environment.sep().[0], v);
  };
  Run.ofBosError(Cmd.resolveCmd(path, prg));
};

let prepareEnv = env => {
  let env =
    switch (env) {
    | CurrentEnv => None
    | CurrentEnvOverride(env) =>
      let env =
        Astring.String.Map.fold(
          Astring.String.Map.add,
          env,
          System.Environment.current,
        );

      Some(env);
    | CustomEnv(env) => Some(env)
    };

  let f = env => {
    let array =
      env
      |> StringMap.bindings
      |> List.map(~f=((name, value)) => name ++ "=" ++ value)
      |> Array.of_list;

    (env, array);
  };

  Option.map(~f, env);
};

let chdir_lock = Lwt_mutex.create();

let withProcess =
    (
      ~env=CurrentEnv,
      ~resolveProgramInEnv=false,
      ~cwd=?,
      ~stdin=?,
      ~stdout=?,
      ~stderr=?,
      cmd,
      f,
    ) => {
  open RunAsync.Syntax;

  let env = prepareEnv(env);

  let* cmd =
    RunAsync.ofRun(
      {
        open Run.Syntax;
        let (prg, args) = Cmd.getToolAndArgs(cmd);
        let* prg =
          switch (resolveProgramInEnv, env) {
          | (true, Some((env, _))) => resolveCmdInEnv(~env, prg)
          | _ => Ok(prg)
          };

        return(("", Array.of_list([prg, ...args])));
      },
    );

  let executeCmd = () =>
    Lwt_process.with_process_none(
      ~env=?Option.map(~f=snd, env),
      ~stdin?,
      ~stdout?,
      ~stderr?,
      cmd,
      f,
    );

  let currentCwd = Sys.getcwd();

  try%lwt(
    switch (cwd) {
    | Some(dir) when currentCwd != dir =>
      Lwt_mutex.with_lock(
        chdir_lock,
        _ => {
          Sys.chdir(dir);
          executeCmd();
        },
      )
    | _ => executeCmd()
    }
  ) {
  | [@implicit_arity] Unix.Unix_error(code, unixFunctionName, parameter) =>
    let msg = Unix.error_message(code);
    errorf(
      "Error occured during ChildProcess.executeCmd: %s %s %s",
      msg,
      unixFunctionName,
      parameter,
    );
  | _ => error("error running subprocess")
  };
};

let run =
    (~env=?, ~resolveProgramInEnv=?, ~stdin=?, ~stdout=?, ~stderr=?, cmd) => {
  open RunAsync.Syntax;
  let f = process =>
    switch%lwt (process#status) {
    | Unix.WEXITED(0) => return()
    | _ =>
      let cmd = Cmd.show(cmd);
      let msg = Printf.sprintf("error running command: %s", cmd);
      error(msg);
    };

  withProcess(
    ~env?,
    ~resolveProgramInEnv?,
    ~stdin?,
    ~stdout?,
    ~stderr?,
    cmd,
    f,
  );
};

let runToStatus =
    (
      ~env=?,
      ~resolveProgramInEnv=?,
      ~cwd=?,
      ~stdin=?,
      ~stdout=?,
      ~stderr=?,
      cmd,
    ) => {
  open RunAsync.Syntax;
  let f = process => {
    let%lwt status = process#status;
    return(status);
  };

  withProcess(
    ~env?,
    ~resolveProgramInEnv?,
    ~cwd?,
    ~stdin?,
    ~stdout?,
    ~stderr?,
    cmd,
    f,
  );
};

let runOut =
    (~env=CurrentEnv, ~resolveProgramInEnv=false, ~stdin=?, ~stderr=?, cmd) => {
  open RunAsync.Syntax;

  /*
   TODO Factor out this into common withProcess and use Lwt_process.with_process_in
    */

  let env =
    switch (env) {
    | CurrentEnv => None
    | CurrentEnvOverride(env) =>
      let env =
        Astring.String.Map.fold(
          Astring.String.Map.add,
          env,
          System.Environment.current,
        );

      Some(env);
    | CustomEnv(env) => Some(env)
    };

  let* cmdLwt =
    RunAsync.ofRun(
      {
        open Run.Syntax;
        let (prg, args) = Cmd.getToolAndArgs(cmd);
        let* prg =
          switch (resolveProgramInEnv, env) {
          | (true, Some(env)) => resolveCmdInEnv(~env, prg)
          | _ => Ok(prg)
          };

        return((prg, Array.of_list([prg, ...args])));
      },
    );

  let env =
    Option.map(env, ~f=env =>
      env
      |> StringMap.bindings
      |> List.map(~f=((name, value)) => name ++ "=" ++ value)
      |> Array.of_list
    );

  let f = process => {
    let%lwt out =
      Lwt.finalize(
        () => Lwt_io.read(process#stdout),
        () => Lwt_io.close(process#stdout),
      );

    switch%lwt (process#status) {
    | Unix.WEXITED(0) => return(out)
    | _ =>
      let msg = Printf.sprintf("running command: %s", Cmd.show(cmd));
      error(msg);
    };
  };

  try%lwt(Lwt_process.with_process_in(~env?, ~stdin?, ~stderr?, cmdLwt, f)) {
  | [@implicit_arity] Unix.Unix_error(err, _, _) =>
    let msg = Unix.error_message(err);
    error(msg);
  | _ => error("error running subprocess")
  };
};
