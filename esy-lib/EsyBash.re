/**
 * Helper method to get the root path of the 'esy-bash' node modules
 */
let getEsyBashRootPath = () =>
  switch (Sys.getenv_opt("ESY__ESY_BASH")) {
  | Some(path) => Path.v(path)
  | None =>
    let resolution =
      NodeResolution.resolve("@prometheansacrifice/esy-bash/package.json");
    switch (resolution) {
    | Ok(path) => Path.parent(path)
    | Error(`Msg(msg)) => Exn.fail(msg)
    };
  };

/**
 * Helper method to get the `cygpath` utility path
 * Used for resolving paths
 */
let getCygPath = () =>
  Path.(getEsyBashRootPath() / ".cygwin" / "bin" / "cygpath.exe");

let getBinPath = () => Path.(getEsyBashRootPath() / ".cygwin" / "bin");

let getEsyBashPath = () =>
  Path.(
    getEsyBashRootPath() / "re" / "_build" / "default" / "bin" / "EsyBash.exe"
  );

let getMingwRuntimePath = () => {
  let rootPath = getEsyBashRootPath();
  Path.(
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
    let binary = Fpath.to_string(rootPath);
    let ic = Unix.open_process_args_in(binary, [|binary, path|]);
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
    Bos.Cmd.of_list([Path.show(esyBashPath), ...allCommands]);
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
      let binary = String.trim(Fpath.to_string(rootPath));
      let ic =
        Unix.open_process_args_in(
          binary,
          [|
            binary,
            "-w",
            Path.normalizePathSepOfFilename(Fpath.to_string(path)),
          |],
        );
      let result = Fpath.v(String.trim(input_line(ic)));
      let () = close_in(ic);
      result;
    | _ => path
    };
  | _ => path
  };

let currentEnvWithMingwInPath = {
  let current = System.Environment.current;
  switch (System.Platform.host) {
  | System.Platform.Windows =>
    let mingw = getMingwRuntimePath();
    let path = [Path.show(mingw), ...System.Environment.path];
    StringMap.add("PATH", System.Environment.join(path), current);
  | _ => current
  };
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
