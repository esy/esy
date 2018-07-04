type t =
  | Darwin
  | Linux
  | Cygwin
  | Windows (* mingw msvc *)
  | Unix (* all other unix-y systems *)
  | Unknown

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

let toString = function
  | Darwin -> "darwin"
  | Linux -> "linux"
  | Cygwin -> "cygwin"
  | Unix -> "unix"
  | Windows -> "windows"
  | Unknown -> "unknown"
