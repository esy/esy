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

module Environment = struct

  let sep =
    match Platform.host with
    | Platform.Windows -> ";"
    | _ -> ":"

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
    match StringMap.find_opt "PATH" current with
    | Some path -> String.split_on_char sep.[0] path
    | None -> []

end
