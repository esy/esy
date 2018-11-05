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
  let program = Sys.argv[0];
  let program =
    switch (NodeResolution.realpath(Fpath.v(program))) {
    | Ok(program) => program
    | Error(`Msg(msg)) => Exn.fail(msg)
    };
  let basedir = Fpath.parent(program);
  let resolution =
    NodeResolution.resolve(
      "../../../../node_modules/esy-bash/package.json",
      basedir,
    );

  switch (coerceFrmMsgOnly(resolution)) {
  | Ok(Some(path)) => Fpath.parent(path)
  | Ok(None) => Exn.fail("unable to find 'esy-bash'")
  | Error(`Msg(msg)) => Exn.fail(msg)
  | Error(`CommandError(cmd, _)) =>
    Exn.failf("command failed: %a", Bos.Cmd.pp, cmd)
  };
};

/**
 * Helper method to get the `cygpath` utility path
 * Used for resolving paths
 */
let getCygPath = () =>
  Fpath.(getEsyBashRootPath() / ".cygwin" / "bin" / "cygpath.exe");

let getBinPath = () => Fpath.(getEsyBashRootPath() / ".cygwin" / "bin");

let getEsyBashPath = () =>
  Fpath.(
    getEsyBashRootPath() / "re" / "_build" / "default" / "bin" / "EsyBash.exe"
  );

let getMingwRuntimePath = () => {
  let rootPath = getEsyBashRootPath();
  Fpath.(
    rootPath
    / ".cygwin"
    / "usr"
    / "x86_64-w64-mingw32"
    / "sys-root"
    / "mingw"
    / "bin"
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
  let environmentFilePath =
    switch (env) {
    | None => []
    | Some(fp) => ["--env", fp]
    };

  switch (System.Platform.host) {
  | Windows =>
    let commands = Bos.Cmd.to_list(cmd);
    let esyBashPath = getEsyBashPath();
    let allCommands = List.append(environmentFilePath, commands);
    Bos.Cmd.of_list([Fpath.to_string(esyBashPath), ...allCommands]);
  | _ => cmd
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

type error = [ | `CommandError(Bos.Cmd.t, Bos.OS.Cmd.status) | `Msg(string)];

/**
 * Helper utility to run a command with 'esy-bash'.
 * On Windows, this runs the command in a Cygwin environment
 * On other platforms, this is equivalent to running the command directly with Bos.OS.Cmd.run
 */
let run = cmd => {
  let cmd = toEsyBashCommand(cmd);
  Bos.OS.Cmd.run(cmd);
};

let runOut = cmd => {
  let cmd = toEsyBashCommand(cmd);
  let ret = Bos.OS.Cmd.(run_out(cmd));
  Bos.OS.Cmd.to_string(ret);
};
