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
  /*** TODO: handle more platforms, right now this is tested only on macOS and Linux */
  let cmd = Bos.Cmd.(v("getconf") % "_NPROCESSORS_ONLN");
  switch (Bos.OS.Cmd.(run_out(cmd) |> to_string)) {
  | Ok(out) =>
    switch (out |> String.trim |> int_of_string_opt) {
    | Some(n) => n
    | None => 1
    }
  | Error(_) => 1
  };
};
