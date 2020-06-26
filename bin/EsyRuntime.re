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

let concurrency = {
  let to_int =
    Option.bind(~f=n_str => n_str |> String.trim |> int_of_string_opt);
  let env_esy_build_concurrency =
    Sys.getenv_opt("ESY_BUILD_CONCURRENCY") |> to_int;
  let env_number_of_processors =
    Sys.getenv_opt("NUMBER_OF_PROCESSORS") |> to_int;

  let getconf_nprocessors = {
    let cmd = Bos.Cmd.(v("getconf") % "_NPROCESSORS_ONLN");
    switch (Bos.OS.Cmd.(run_out(cmd) |> to_string)) {
    | Ok(n_str) => n_str |> String.trim |> int_of_string_opt
    | Error(_) => None
    };
  };
  switch (env_esy_build_concurrency) {
  | Some(n) => n
  | None =>
    switch (getconf_nprocessors, env_number_of_processors) {
    | (Some(n), _) => n
    | (None, Some(n)) => n
    | (None, None) => 1
    }
  };
};
