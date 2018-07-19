module Path = EsyLib.Path;

type pattern =
  | Subpath(string)
  | Regex(string);

type config = {allowWrite: list(pattern)};

module Darwin = {
  let renderConfig = config => {
    open Sexp;
    let v = x => Value(L(x));
    let renderAllowWrite =
      List.map(
        fun
        | Subpath(p) =>
          v([I("allow"), I("file-write*"), L([I("subpath"), S(p)])])
        | Regex(p) =>
          v([I("allow"), I("file-write*"), L([I("regex"), S(p)])]),
      );
    let doc =
      [
        v([I("version"), N(1.0)]),
        v([I("allow"), I("default")]),
        v([I("deny"), I("file-write*"), L([I("subpath"), S("/")])]),
        v([
          I("allow"),
          I("file-write*"),
          L([I("literal"), S("/dev/null")]),
        ]),
      ]
      @ renderAllowWrite(config.allowWrite);
    render(doc);
  };
  let sandboxExec = config => {
    open Run;
    let configData = renderConfig(config);
    let%bind configFilename = putTempFile(configData);
    let prepare = (~env, command) => {
      open Bos.OS.Cmd;
      let sandboxCommand =
        Bos.Cmd.of_list([
          "sandbox-exec",
          "-f",
          Path.to_string(configFilename),
        ]);
      let command = Bos.Cmd.(sandboxCommand %% command);

      let exec = (~err) => run_io(~env, ~err, command);
      Ok(exec);
    };
    Ok(prepare);
  };
};

let convertEnvToJsonString = env => {
  let json = BuildTask.Env.to_yojson(env);
  Yojson.to_string(json);
};

module Windows = {
  let sandboxExec = _config => {
    let prepare = (~env, command) => {
      open Run;
      open Bos.OS.Cmd;

      /*
       * `esy-bash` takes an optional `--env` parameter with the
       * environment variables that should be used for the bash session.
       *
       * Just passing the env directly to esy-bash doesn't work,
       * because we need the current PATH/env to pick up node and run the shell
       */
      let jsonString = convertEnvToJsonString(env);
      let%bind environmentTempFile = putTempFile(jsonString);
      let commandAsList = Bos.Cmd.to_list(command);

      /* Normalize slashes in the command we send to esy-bash */
      let normalizedCommands =
        Bos.Cmd.of_list(
          List.map(EsyLib.Path.normalizePathSlashes, commandAsList),
        );
      let%bind augmentedEsyCommand =
        EsyLib.EsyBash.toEsyBashCommand(
          ~env=Some(Fpath.to_string(environmentTempFile)),
          normalizedCommands,
        );

      let exec = (~err) => run_io(~err, augmentedEsyCommand);
      Ok(exec);
    };
    Ok(prepare);
  };
};

module NoSandbox = {
  let sandboxExec = _config => {
    let prepare = (~env, command) => {
      let exec = (~err) => Bos.OS.Cmd.run_io(~env, ~err, command);
      Ok(exec);
    };
    Ok(prepare);
  };
};

let sandboxExec = config =>
  switch (EsyLib.System.Platform.host) {
  | Windows => Windows.sandboxExec(config)
  | Darwin => Darwin.sandboxExec(config)
  | _ => NoSandbox.sandboxExec(config)
  };
