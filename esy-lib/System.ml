module Platform = struct
  type t =
    | Darwin
    | Linux
    | Cygwin
    | Windows (* mingw msvc *)
    | Unix (* all other unix-y systems *)
    | Unknown
    [@@deriving ord]

  let show = function
    | Darwin -> "darwin"
    | Linux -> "linux"
    | Cygwin -> "cygwin"
    | Unix -> "unix"
    | Windows -> "windows"
    | Unknown -> "unknown"

  let pp fmt v = Fmt.string fmt (show v)

  let to_yojson v = `String (show v)
  let of_yojson = function
    | `String "darwin" -> Ok Darwin
    | `String "linux" -> Ok Linux
    | `String "cygwin" -> Ok Cygwin
    | `String "unix" -> Ok Unix
    | `String "windows" -> Ok Windows
    | `String "unknown" -> Ok Unknown
    | `String v -> Result.errorf "unknown platform: %s" v
    | _json -> Result.error "System.Platform.t: expected string"

  let host =
    let uname () =
      let ic = Unix.open_process_in "uname" in
      let uname = input_line ic in
      let () = close_in ic in
      match String.lowercase_ascii uname with
      | "linux" -> Linux
      | "darwin" -> Darwin
      | _ -> Unix
    in
    match Sys.os_type with
      | "Unix" -> uname ()
      | "Win32" -> Windows
      | "Cygwin" -> Cygwin
      | _ -> Unknown

end

module Arch = struct
  type t =
    | X86_32
    | X86_64
    | Ppc32
    | Ppc64
    | Arm32
    | Arm64
    | Unknown
    [@@deriving ord]

  let show = function
    | X86_32 -> "x86_32"
    | X86_64 -> "x86_64"
    | Ppc32 -> "ppc32"
    | Ppc64 -> "ppc64"
    | Arm32 -> "arm32"
    | Arm64 -> "arm64"
    | Unknown -> "unknown"

  let pp fmt v = Fmt.string fmt (show v)

  let to_yojson v = `String (show v)

  let of_yojson = function
    | `String "x86_32" -> Ok X86_32
    | `String "x86_64" -> Ok X86_64
    | `String "ppc32" -> Ok Ppc32
    | `String "ppc64" -> Ok Ppc64
    | `String "arm32" -> Ok Arm32
    | `String "arm64" -> Ok Arm64
    | `String "unknown" -> Ok Unknown
    | `String v -> Result.errorf "unknown architecture: %s" v
    | _json -> Result.error "System.Arch.t: expected string"

  let host =
    let uname () =
      let cmd =
          match Platform.host with
          | Windows -> "echo %PROCESSOR_ARCHITECTURE%"
          | _ -> "uname -m"
      in
      let ic = Unix.open_process_in cmd in
      let uname = input_line ic in
      let () = close_in ic in
      match String.trim (String.lowercase_ascii uname) with
      (* Return values for Windows PROCESSOR_ARCHITECTURE environment variable *)
      | "x86" -> X86_32
      | "x86_64" -> X86_64
      | "amd64" -> X86_64
      (* Return values for uname on other platforms *)
      | "ppc32" -> Ppc32
      | "ppc64" -> Ppc64
      | "arm32" -> Arm32
      | "arm64" -> Arm64
      | _ -> Unknown
    in
    uname ()
end

external checkLongPathRegistryKey: unit -> bool = "esy_win32_check_long_path_regkey"

let supportsLongPaths () =
  match Sys.win32 with
  | false -> true
  | true -> checkLongPathRegistryKey()

module Environment = struct
  let sep ?(platform=Platform.host) ?name () =
    match name, platform with
    (* a special case for cygwin + OCAMLPATH: it is expected to use ; as separator *)
    | Some "OCAMLPATH", (Platform.Linux | Darwin | Unix | Unknown) -> ":"
    | Some "OCAMLPATH", (Cygwin | Windows) -> ";"
    | _, (Linux | Darwin | Unix | Unknown | Cygwin) -> ":"
    | _, Windows -> ";"

  let split ?platform ?name value =
    let sep = sep ?platform ?name () in
    String.split_on_char sep.[0] value

  let join ?platform ?name value =
    let sep = sep ?platform ?name () in
    String.concat sep value

  let current =
    let f map item =
      let idx = String.index item '=' in
      let name = String.sub item 0 idx in
      let name =
        match Platform.host with
        | Platform.Windows -> String.uppercase_ascii name
        | _ -> name
      in
      let value = String.sub item (idx + 1) (String.length item - idx - 1) in
      StringMap.add name value map
    in
    let items = Unix.environment () in
    Array.fold_left f StringMap.empty items

  let path =
    let name = "PATH" in
    match StringMap.find_opt name current with
    | Some path -> split ~name path
    | None -> []

  let normalizeNewLines s =
    Str.global_replace (Str.regexp_string "\r\n") "\n" s
end
