let currentWorkingDir = Path.v(Sys.getcwd());
let currentExecutable = Path.v(Sys.executable_name);

let version = "0.6.14";

let detect_concurrency_from_env = () => {
  let to_int =
    Option.bind(~f=n_str => n_str |> String.trim |> int_of_string_opt);

  switch (System.Platform.host) {
  /* only Win32, as cygwin will have getconf */
  | Windows => Sys.getenv_opt("NUMBER_OF_PROCESSORS") |> to_int
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
