module System = EsyLib.System;

/** 
 * Helper method to get the root path of the 'esy-bash' node modules
 */
let getEsyBashRootPath = () => {
  open Run;
  let program = Sys.argv[0];
  let%bind program = realpath(v(program));
  let basedir = Fpath.parent(program);
  let resolution =
      EsyLib.NodeResolution.resolve(
        "../../../../node_modules/esy-bash/package.json",
        basedir,
      );

  switch%bind (Run.coerceFrmMsgOnly(resolution)) {
    | Some(path) => Ok(Fpath.parent(path))
    | None => Error(`Msg("Unable to find 'esy-bash'"))
  };
};

/**
 * Helper method to get the `cygpath` utility path
 * Used for resolving paths
 */
let getCygPath = () => {
    open Run;
    let%bind rootPath = getEsyBashRootPath();
    Ok(Fpath.(rootPath / ".cygwin" / "bin" / "cygpath.exe"));
};

let getEsyBashPath = () => {
    open Run;
    let%bind rootPath = getEsyBashRootPath();
    Ok(Fpath.(rootPath / "bin" / "esy-bash.js"));
};

/**
* Helper utility to normalize paths to a cygwin style,
* ie, "C:\temp" -> "/cygdrive/c/temp"
* On non-Windows platforms, this is a noop
*/
let normalizePathForCygwin = (path) => {
    open Run;
    switch (System.host) {
        | System.Windows => {
            let%bind rootPath = getCygPath();
            let ic = Unix.open_process_in(Fpath.to_string(rootPath) ++ " \"" ++ path ++ " \"")
            let result = String.trim(input_line(ic));
            let () = close_in(ic);
            Ok(result);
        };
        | _ => Ok(path)
    }
};

let toEsyBashCommand = (~env=None, cmd) => {
    open Run;
    let environmentFilePath = switch (env) {
        | None => []
        | Some(fp) => ["--env", fp]
    };

    switch (System.host) {
        | Windows => 
            let commands = Bos.Cmd.to_list(cmd);
            let%bind esyBashPath = getEsyBashPath();
            let allCommands = List.append(environmentFilePath, commands);
            Ok(Bos.Cmd.of_list([
                "node",
                Fpath.to_string(esyBashPath),
                ...allCommands,
            ]));
        | _ => Ok(cmd)
        };
};

/**
 * Helper utility to run a command with 'esy-bash'.
 * On Windows, this runs the command in a Cygwin environment
 * On other platforms, this is equivalent to running the command directly with Bos.OS.Cmd.run
 */
let run = (cmd) => {
    open Run;
    let%bind augmentedCommand = toEsyBashCommand(cmd);
    Bos.OS.Cmd.run(augmentedCommand);
};
