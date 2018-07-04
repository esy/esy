type t =
  | Darwin
  | Linux
  | Cygwin
  | Other of string

let isCygwin =
  let test = Re.(compile (seq [bos; str "cygwin"])) in
  Re.execp test

let uname () =
  let ic = Unix.open_process_in "uname" in
  let uname = input_line ic in
  let () = close_in ic in
  match String.lowercase_ascii uname with
  | "linux" -> Linux
  | "darwin" -> Darwin
  | name ->
    if isCygwin name
    then Cygwin
    else Other name

let host = uname ()

let toString = function
  | Darwin -> "darwin"
  | Linux -> "linux"
  | Cygwin -> "cygwin"
  | Other _ -> "unknown"
