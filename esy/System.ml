type system =
  | Darwin
  | Linux
  | Windows
  | Cygwin
  | Other

let uname () =
  let ic = Unix.open_process_in("uname") in
  let uname = input_line(ic) in
  let () = close_in(ic) in
  match String.lowercase_ascii(uname) with
  | "linux" -> Linux
  | "darwin" -> Darwin
  | _ -> Other

let gethost () =
  match Sys.os_type with
  | "Unix" -> uname ()
  | "Win32" -> Windows
  | "Cygwin" -> Cygwin
  | _ -> Other

let host = gethost ()
