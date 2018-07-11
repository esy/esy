let (/) = Fpath.(/);

let v = Fpath.v;

type t('a, 'b) =
  result(
    'a,
    [> | `Msg(string) | `CommandError(Bos.Cmd.t, Bos.OS.Cmd.status)] as 'b,
  );

let coerceFrmMsgOnly = x => (x: result(_, [ | `Msg(string)]) :> t(_, _));


let rec realpath = (p: Fpath.t) => {
  open Result.Syntax;
  let%bind p =
    if (Fpath.is_abs(p)) {
      Ok(p);
    } else {
      let%bind cwd = Bos.OS.Dir.current();
      Ok(p |> Fpath.append(cwd) |> Fpath.normalize);
    };
  let _realpath = (p: Fpath.t) => {
    let isSymlinkAndExists = p =>
      switch (Bos.OS.Path.symlink_stat(p)) {
      | Ok({Unix.st_kind: Unix.S_LNK, _}) => Ok(true)
      | _ => Ok(false)
      };
    if (Fpath.is_root(p)) {
      Ok(p);
    } else {
      let%bind isSymlink = isSymlinkAndExists(p);
      if (isSymlink) {
        let%bind target = Bos.OS.Path.symlink_target(p);
        realpath(
          target |> Fpath.append(Fpath.parent(p)) |> Fpath.normalize,
        );
      } else {
        let parent = p |> Fpath.parent |> Fpath.rem_empty_seg;
        let%bind parent = realpath(parent);
        Ok(parent / Fpath.basename(p));
      };
    };
  };
  _realpath(p);
};


/**
 * Helper method to get the root path of the 'esy-bash' node modules
 */
let getEsyBashRootPath = () => {
  open Result.Syntax;
  let program = Sys.argv[0];
  let%bind realpath = realpath(Fpath.v(program))
  let basedir = Fpath.parent(realpath);
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
    open Result.Syntax;
    let%bind rootPath = getEsyBashRootPath();
    Ok(Fpath.(rootPath / ".cygwin" / "bin" / "cygpath.exe"));
};

let getEsyBashPath = () => {
    open Result.Syntax;
    let%bind rootPath = getEsyBashRootPath();
    Ok(Fpath.(rootPath / "bin" / "esy-bash.js"));
};

/**
* Helper utility to normalize paths to a cygwin style,
* ie, "C:\temp" -> "/cygdrive/c/temp"
* On non-Windows platforms, this is a noop
*/
let normalizePathForCygwin = (path) => {
    open Result.Syntax;
    switch (System.host) {
        | System.Windows => {
            let%bind rootPath = getCygPath();
            let ic = Unix.open_process_in(Fpath.to_string(rootPath) ++ " \"" ++ path ++ " \"")
            let result = String.trim(input_line(ic));
            let () = close_in(ic);
            Ok(result);
        };
        | _ => Ok(path)
    };
};

/**
* Helper utility to normalize paths to a Windows style.
* ie, "/usr/bin" -> "C:\path\to\installed\cygwin\usr\bin"
* On non-windows platforms, this is a no-op
*/
let normalizePathForWindows = (path) => {
    open Result.Syntax;
    switch (System.host) {
        | System.Windows => {
            let%bind rootPath = getCygPath();
            /* Use the `cygpath` utility with the `-w` flag to resolve to a Windows path */
            let ic = Unix.open_process_in(Fpath.to_string(rootPath) ++ "-w \"" ++ path ++ " \"")
            let result = String.trim(input_line(ic));
            let () = close_in(ic);
            Ok(result);
        };
        | _ => Ok(path)
    };
};

/**
 * Helper utility to run a command with 'esy-bash'.
 * On Windows, this runs the command in a Cygwin environment
 * On other platforms, this is equivalent to running the command directly with Bos.OS.Cmd.run
 */
let run = (cmd) => {
    switch (System.host) {
        | Windows =>
            open Result.Syntax;
            let commands = Bos.Cmd.to_list(cmd);
            let%bind esyBashPath = getEsyBashPath()
            let esyBashCommand = Bos.Cmd.of_list([
                "node",
                Fpath.to_string(esyBashPath),
                ...commands,
            ]);
            Bos.OS.Cmd.run(esyBashCommand)
        | _ => Bos.OS.Cmd.run(cmd)
    };
};
