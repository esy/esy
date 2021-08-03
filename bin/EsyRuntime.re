let currentWorkingDir = Path.v(Sys.getcwd());
let currentExecutable = Path.v(Sys.executable_name);

let version = "0.6.11";

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
