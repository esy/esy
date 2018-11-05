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
let getCygPath = () => {
  let rootPath = getEsyBashRootPath();
  switch (rootPath) {
  | Ok(rootPath) => Fpath.(rootPath / ".cygwin" / "bin" / "cygpath.exe")
  | Error(`Msg(err)) => failwith(err)
  | Error(`CommandError(cmd, _)) =>
    Exn.failf("command failed: %a", Bos.Cmd.pp, cmd)
  };
};

let getBinPath = () => {
  open Result.Syntax;
  let%bind rootPath = getEsyBashRootPath();
  Ok(Fpath.(rootPath / ".cygwin" / "bin"));
};

let getEsyBashPath = () => {
  open Result.Syntax;
  let%bind rootPath = getEsyBashRootPath();
  Ok(Fpath.(rootPath / "re" / "_build" / "default" / "bin" / "EsyBash.exe"));
};

let getMingwRuntimePath = () => {
  open Result.Syntax;
  let%bind rootPath = getEsyBashRootPath();
  Ok(
    Fpath.(
      rootPath
      / ".cygwin"
      / "usr"
      / "x86_64-w64-mingw32"
      / "sys-root"
      / "mingw"
      / "bin"
    ),
  );
};

/**
* Helper utility to normalize paths to a cygwin style,
* ie, "C:\temp" -> "/cygdrive/c/temp"
* On non-Windows platforms, this is a noop
*/
let normalizePathForCygwin = path =>
  switch (System.Platform.host) {
  | System.Platform.Windows =>
    let rootPath = getCygPath();
    let ic =
      Unix.open_process_in(
        Fpath.to_string(rootPath) ++ " \"" ++ path ++ " \"",
      );
    let result = String.trim(input_line(ic));
    let () = close_in(ic);
    result;
  | _ => path
  };

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
    Ok(Bos.Cmd.of_list([Fpath.to_string(esyBashPath), ...allCommands]));
  | _ => Ok(cmd)
  };
};

/**
* Helper utility to normalize paths to a Windows style.
* ie, "/usr/bin" -> "C:\path\to\installed\cygwin\usr\bin"
* On non-windows platforms, this is a no-op
*/
let normalizePathForWindows = (path: Fpath.t) =>
  switch (System.Platform.host) {
  | System.Platform.Windows =>
    let pathAsString = Fpath.to_string(path);
    switch (pathAsString.[0]) {
    /* We assume that if the path coming in to normalize is a leading slash,
     * it should be converted from a Unix path to a Windows path.
     */
    | '\\' =>
      let rootPath = getCygPath();
      /* Use the `cygpath` utility with the `-w` flag to resolve to a Windows path */
      let commandToRun =
        String.trim(Fpath.to_string(rootPath))
        ++ " -w "
        ++ Path.normalizePathSlashes(Fpath.to_string(path));
      let ic = Unix.open_process_in(commandToRun);
      let result = Fpath.v(String.trim(input_line(ic)));
      let () = close_in(ic);
      result;
    | _ => path
    };
  | _ => path
  };

/**
 * Helper utility to run a command with 'esy-bash'.
 * On Windows, this runs the command in a Cygwin environment
 * On other platforms, this is equivalent to running the command directly with Bos.OS.Cmd.run
 */
let run = cmd => {
  open Result.Syntax;
  let%bind augmentedCommand = toEsyBashCommand(cmd);
  Bos.OS.Cmd.run(augmentedCommand);
};

let runOut = cmd => {
  open Result.Syntax;
  let%bind augmentedCommand = toEsyBashCommand(cmd);
  let ret = Bos.OS.Cmd.(run_out(augmentedCommand));
  Bos.OS.Cmd.to_string(ret);
};
