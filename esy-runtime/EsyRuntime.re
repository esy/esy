open RunAsync.Syntax;

let currentWorkingDir = Path.v(Sys.getcwd());
let currentExecutable = Path.v(Sys.executable_name);

let version = EsyVersion.version;

let detect_concurrency_from_env = () => {
  let to_int =
    Option.bind(~f=n_str => n_str |> String.trim |> int_of_string_opt);

  switch (System.Platform.host) {
  /* only Win32, as cygwin will have getconf */
  | Windows_mingw => Sys.getenv_opt("NUMBER_OF_PROCESSORS") |> to_int
  | _ =>
    let cmd = Bos.Cmd.(v("getconf") % "_NPROCESSORS_ONLN");
    Bos.OS.Cmd.(run_out(cmd) |> to_string)
    |> Stdlib.Result.to_option
    |> to_int;
  };
};

let env_concurrency = detect_concurrency_from_env();

let concurrency = userDefinedValue => {
  switch (userDefinedValue) {
  | Some(n) => n
  | None => env_concurrency |> Option.orDefault(~default=1)
  };
};

let exePath = () => {
  switch (System.Platform.host) {
  | Linux => Unix.readlink("/proc/self/exe")
  | Darwin
  | Cygwin
  | Windows_mingw
  | Unix
  | Unknown => Sys.argv[0]
  // TODO cross-platform solution to getting full path of the current executable.
  // Linux has /proc/self/exe. Macos ?? Windows GetModuleFileName()
  // https://stackoverflow.com/a/1024937
  };
};

let resolveRelativeTo = (~internalCommandName, path) => {
  let dir = Path.(path |> parent |> parent);
  let path = Path.(dir / "lib" / "esy" / internalCommandName);
  let path = System.Platform.isWindows ? Path.addExt("exe", path) : path;
  let* exists = Fs.exists(path);
  let v = exists ? Some(path) : None;
  RunAsync.return(v);
};

let getInternalCommand = (internalCommandName, ()) => {
  let* exePath = exePath() |> Path.ofString |> RunAsync.ofBosError;
  let* path = {
    let* v = resolveRelativeTo(~internalCommandName, exePath);
    switch (v) {
    | Some(path) => RunAsync.return(path)
    | None =>
      let* path =
        Sys.getenv_opt("_")
        |> RunAsync.ofOption(
             ~err=
               "Could not find _ in the environment. We look this variable up to resolve internal commands",
           );
      let* path = Path.ofString(path) |> RunAsync.ofBosError;
      let* v = resolveRelativeTo(~internalCommandName, path);
      switch (v) {
      | None =>
        RunAsync.errorf(
          "Could not find internal command %s",
          internalCommandName,
        )
      | Some(path) => RunAsync.return(path)
      };
    };
  };
  RunAsync.return @@ Cmd.ofPath @@ path;
};

let getRewritePrefixCommand = getInternalCommand("esyRewritePrefixCommand");
let getEsyBuildPackageCommand = getInternalCommand("esyBuildPackageCommand");
let getEsySolveCudfCommand = getInternalCommand("esySolveCudfCommand");
