module Platform = {
  [@deriving ord]
  type t =
    | Darwin
    | Linux
    | Cygwin
    | Windows /* mingw msvc */
    | Unix /* all other unix-y systems */
    | Unknown;

  let show =
    fun
    | Darwin => "darwin"
    | Linux => "linux"
    | Cygwin => "cygwin"
    | Unix => "unix"
    | Windows => "windows"
    | Unknown => "unknown";

  let pp = (fmt, v) => Fmt.string(fmt, show(v));

  let to_yojson = v => `String(show(v));
  let of_yojson =
    fun
    | `String("darwin") => Ok(Darwin)
    | `String("linux") => Ok(Linux)
    | `String("cygwin") => Ok(Cygwin)
    | `String("unix") => Ok(Unix)
    | `String("windows") => Ok(Windows)
    | `String("unknown") => Ok(Unknown)
    | `String(v) => Result.errorf("unknown platform: %s", v)
    | _json => Result.error("System.Platform.t: expected string");

  let host = {
    let uname = () => {
      let ic = Unix.open_process_in("uname");
      let uname = input_line(ic);
      let () = close_in(ic);
      switch (String.lowercase_ascii(uname)) {
      | "linux" => Linux
      | "darwin" => Darwin
      | _ => Unix
      };
    };

    switch (Sys.os_type) {
    | "Unix" => uname()
    | "Win32" => Windows
    | "Cygwin" => Cygwin
    | _ => Unknown
    };
  };

  let isWindows =
    switch (host) {
    | Windows => true
    | _ => false
    };
};

module Arch = {
  [@deriving ord]
  type t =
    | X86_32
    | X86_64
    | Ppc32
    | Ppc64
    | Arm32
    | Arm64
    | Unknown;

  let show =
    fun
    | X86_32 => "x86_32"
    | X86_64 => "x86_64"
    | Ppc32 => "ppc32"
    | Ppc64 => "ppc64"
    | Arm32 => "arm32"
    | Arm64 => "arm64"
    | Unknown => "unknown";

  let pp = (fmt, v) => Fmt.string(fmt, show(v));

  let to_yojson = v => `String(show(v));

  let of_yojson =
    fun
    | `String("x86_32") => Ok(X86_32)
    | `String("x86_64") => Ok(X86_64)
    | `String("ppc32") => Ok(Ppc32)
    | `String("ppc64") => Ok(Ppc64)
    | `String("arm32") => Ok(Arm32)
    | `String("arm64") => Ok(Arm64)
    | `String("unknown") => Ok(Unknown)
    | `String(v) => Result.errorf("unknown architecture: %s", v)
    | _json => Result.error("System.Arch.t: expected string");

  let host = {
    let uname = () => {
      let ic = Unix.open_process_in("uname -m");

      let uname = input_line(ic);
      let () = close_in(ic);
      uname;
    };

    let convert = uname => {
      switch (String.trim(String.lowercase_ascii(uname))) {
      /* Return values for Windows PROCESSOR_ARCHITECTURE environment variable */
      | "x86" => X86_32
      | "x86_64" => X86_64
      | "amd64" => X86_64
      /* Return values for uname on other platforms */
      | "ppc32" => Ppc32
      | "ppc64" => Ppc64
      | "arm32" => Arm32
      | "arm64" => Arm64
      | _ => Unknown
      };
    };

    switch (Platform.host) {
    // Should be defined at session statup globally
    | Windows => convert(Sys.getenv("PROCESSOR_ARCHITECTURE"))
    | _ => convert(uname())
    };
  };
};

external checkLongPathRegistryKey: unit => bool =
  "esy_win32_check_long_path_regkey";

external ensureMinimumFileDescriptors: unit => unit =
  "esy_ensure_minimum_file_descriptors";

external moveFile: (string, string) => unit = "esy_move_file";

let getumask = () =>
  try({
    let oldMask = Unix.umask(0);
    ignore(Unix.umask(oldMask));
    oldMask;
  }) {
  // In case of windows Unix.umask is not implemented
  | Invalid_argument(_) => 0
  };

let supportsLongPaths = () =>
  switch (Sys.win32) {
  | false => true
  | true => checkLongPathRegistryKey()
  };

module Environment = {
  let sep = (~platform=Platform.host, ~name=?, ()) =>
    switch (name, platform) {
    /* a special case for cygwin + OCAMLPATH: it is expected to use ; as separator */
    | (Some("OCAMLPATH"), Platform.Linux | Darwin | Unix | Unknown) => ":"
    | (Some("OCAMLPATH"), Cygwin | Windows) => ";"
    | (_, Linux | Darwin | Unix | Unknown | Cygwin) => ":"
    | (_, Windows) => ";"
    };

  let split = (~platform=?, ~name=?, value) => {
    let sep = sep(~platform?, ~name?, ());
    String.split_on_char(sep.[0], value);
  };

  let join = (~platform=?, ~name=?, value) => {
    let sep = sep(~platform?, ~name?, ());
    String.concat(sep, value);
  };

  let current = {
    let f = (map, item) => {
      let idx = String.index(item, '=');
      let name = String.sub(item, 0, idx);
      let name =
        switch (Platform.host) {
        | Platform.Windows => String.uppercase_ascii(name)
        | _ => name
        };

      let value = String.sub(item, idx + 1, String.length(item) - idx - 1);
      StringMap.add(name, value, map);
    };

    let items = Unix.environment();
    Array.fold_left(f, StringMap.empty, items);
  };

  let path = {
    let name = "PATH";
    switch (StringMap.find_opt(name, current)) {
    | Some(path) => split(~name, path)
    | None => []
    };
  };

  let normalizeNewLines = s =>
    Str.global_replace(Str.regexp_string("\r\n"), "\n", s);
};
