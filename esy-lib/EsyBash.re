type t('a, 'b) =
  result(
    'a,
    [> | `Msg(string) | `CommandError(Bos.Cmd.t, Bos.OS.Cmd.status)] as 'b,
  );

let coerceFrmMsgOnly = x => (x: result(_, [ | `Msg(string)]) :> t(_, _));

/**
 * Helper method to get the root path of the 'esy-bash' node modules
 */
let getEsyBashRootPath = () => {
  open Result.Syntax;
  let program = Sys.argv[0];
  let%bind program = NodeResolution.realpath(Fpath.v(program));
  let basedir = Fpath.parent(program);
  let resolution =
    NodeResolution.resolve(
      "../../../../node_modules/esy-bash/package.json",
      basedir,
    );

  switch%bind (coerceFrmMsgOnly(resolution)) {
  | Some(path) => Ok(Fpath.parent(path))
  | None => Error(`Msg("Unable to find 'esy-bash'"))
  };
};

/**
 * Helper method to get the `cygpath` utility path
 * Used for resolving paths
 */
let getCygPath = () =>
  Result.Syntax.(
    {
      let%bind rootPath = getEsyBashRootPath();
      Ok(Fpath.(rootPath / ".cygwin" / "bin" / "cygpath.exe"));
    }
  );

let getEsyBashPath = () =>
  Result.Syntax.(
    {
      let%bind rootPath = getEsyBashRootPath();
      Ok(Fpath.(rootPath / "bin" / "esy-bash.js"));
    }
  );

/**
* Helper utility to normalize paths to a cygwin style,
* ie, "C:\temp" -> "/cygdrive/c/temp"
* On non-Windows platforms, this is a noop
*/
let normalizePathForCygwin = path =>
  Result.Syntax.(
    switch (System.Platform.host) {
    | System.Platform.Windows =>
      let%bind rootPath = getCygPath();
      let ic =
        Unix.open_process_in(
          Fpath.to_string(rootPath) ++ " \"" ++ path ++ " \"",
        );
      let result = String.trim(input_line(ic));
      let () = close_in(ic);
      Ok(result);
    | _ => Ok(path)
    }
  );

let toEsyBashCommand = (~env=None, cmd) => {
  open Result.Syntax;
  let environmentFilePath =
    switch (env) {
    | None => []
    | Some(fp) => ["--env", fp]
    };

  switch (System.Platform.host) {
  | Windows =>
    let commands = Bos.Cmd.to_list(cmd);
    let%bind esyBashPath = getEsyBashPath();
    let allCommands = List.append(environmentFilePath, commands);
    Ok(
      Bos.Cmd.of_list([
        "node",
        Fpath.to_string(esyBashPath),
        ...allCommands,
      ]),
    );
  | _ => Ok(cmd)
  };
};

/**
* Helper utility to normalize paths to a Windows style.
* ie, "/usr/bin" -> "C:\path\to\installed\cygwin\usr\bin"
* On non-windows platforms, this is a no-op
*/
let normalizePathForWindows = (path: Fpath.t) =>
  Result.Syntax.(
    switch (System.Platform.host) {
    | System.Platform.Windows =>
      let pathAsString = Fpath.to_string(path);
      switch (pathAsString.[0]) {
      /* We assume that if the path coming in to normalize is a leading slash,
       * it should be converted from a Unix path to a Windows path.
       */
      | '\\' =>
        let%bind rootPath = getCygPath();
        /* Use the `cygpath` utility with the `-w` flag to resolve to a Windows path */
        let commandToRun =
          String.trim(Fpath.to_string(rootPath))
          ++ " -w "
          ++ Path.normalizePathSlashes(Fpath.to_string(path));
        let ic = Unix.open_process_in(commandToRun);
        let result = Fpath.v(String.trim(input_line(ic)));
        let () = close_in(ic);
        Ok(result);
      | _ => Ok(path)
      };
    | _ => Ok(path)
    }
  );

/**
 * Helper utility to run a command with 'esy-bash'.
 * On Windows, this runs the command in a Cygwin environment
 * On other platforms, this is equivalent to running the command directly with Bos.OS.Cmd.run
 */
let run = cmd =>
  Result.Syntax.(
    {
      let%bind augmentedCommand = toEsyBashCommand(cmd);
      Bos.OS.Cmd.run(augmentedCommand);
    }
  );
