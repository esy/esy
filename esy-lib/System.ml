module Platform = struct
  type t =
    | Darwin
    | Linux
    | Cygwin
    | Windows (* mingw msvc *)
    | Unix (* all other unix-y systems *)
    | Unknown
    [@@deriving eq, ord]

  let show = function
    | Darwin -> "darwin"
    | Linux -> "linux"
    | Cygwin -> "cygwin"
    | Unix -> "unix"
    | Windows -> "windows"
    | Unknown -> "unknown"

  let pp fmt v = Fmt.string fmt (show v)

  let toString = show

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
    [@@deriving eq, ord]

  let show = function
    | X86_32 -> "x86_32"
    | X86_64 -> "x86_64"
    | Ppc32 -> "ppc32"
    | Ppc64 -> "ppc64"
    | Arm32 -> "arm32"
    | Arm64 -> "arm64"
    | Unknown -> "unknown"

  let pp fmt v = Fmt.string fmt (show v)

  let toString = show

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

module Environment = struct

  let sep ?(platform=Platform.host) ?name () =
    match name, platform with
    (* a special case for cygwin + OCAMLPATH: it is expected to use ; as separator *)
    | Some "OCAMLPATH", (Platform.Linux | Darwin | Unix | Unknown) -> ":"
    | Some "OCAMLPATH", (Cygwin | Windows) -> ";"
    | _, (Linux | Darwin | Unix | Unknown | Cygwin) -> ":"
    | _, Windows -> ";"

  let current =
    let f map item =
      let idx = String.index item '=' in
      let name = String.sub item 0 idx in
      let value = String.sub item (idx + 1) (String.length item - idx - 1) in
      StringMap.add name value map
    in
    let items = Unix.environment () in
    Array.fold_left f StringMap.empty items

  let path =
    let sep = sep () in
    match StringMap.find_opt "PATH" current with
    | Some path -> String.split_on_char sep.[0] path
    | None -> []

  let homeDir =
    (** if HOME is set use that *)
    match (Sys.getenv_opt("HOME"), Platform.host) with
    | (Some(dir), _) -> dir
    | (None, Platform.Windows) -> Sys.getenv("USERPROFILE")
    | _ -> raise (EnvironmentNotFound "Could not find HOME dir")
    match Platform.host with
    | Platform.Windows -> Sys.getenv("USERPROFILE")
    | _ -> Sys.getenv("HOME")

end
