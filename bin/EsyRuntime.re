let currentWorkingDir = Path.v(Sys.getcwd());
let currentExecutable = Path.v(Sys.executable_name);

let resolve = req =>
  switch (NodeResolution.resolve(req)) {
  | Ok(path) => path
  | Error(`Msg(err)) => failwith(err)
  };

module EsyPackageJson = {
  [@deriving of_yojson({strict: false})]
  type t = {version: string};

  let read = () => {
    let pkgJson = {
      open RunAsync.Syntax;
      let filename = resolve("../../../package.json");
      let%bind data = Fs.readFile(filename);
      Lwt.return(Json.parseStringWith(of_yojson, data));
    };
    Lwt_main.run(pkgJson);
  };
};

let version =
  switch (EsyPackageJson.read()) {
  | Ok(pkgJson) => pkgJson.EsyPackageJson.version
  | Error(err) =>
    let msg = {
      let err = Run.formatError(err);
      Printf.sprintf(
        "invalid esy installation: cannot read package.json %s",
        err,
      );
    };
    failwith(msg);
  };

let concurrency = userDefinedValue => {
  let to_int =
    Option.bind(~f=n_str => n_str |> String.trim |> int_of_string_opt);
  let detect_concurrency_from_env = () =>
    switch (System.Platform.host) {
    /* only Win32, as cygwin will have getconf */
    | Windows => Sys.getenv_opt("NUMBER_OF_PROCESSORS") |> to_int
    | _ =>
      let cmd = Bos.Cmd.(v("getconf") % "_NPROCESSORS_ONLN");
      Bos.OS.Cmd.(run_out(cmd) |> to_string)
      |> Stdlib.Result.to_option
      |> to_int;
    };

  switch (userDefinedValue) {
  | Some(n) => n
  | None => detect_concurrency_from_env() |> Option.orDefault(~default=1)
  };
};
