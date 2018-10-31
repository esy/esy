
type os =
    | Windows
    | Mac
    | Linux
    | Unknown

let uname () =
    let ic = Unix.open_process_in "uname" in
    let uname = input_line ic in
    let () = close_in ic in
    uname;;

let get_os = 
    match Sys.os_type with
    | "Win32" -> Windows
    | _ -> match uname () with
        | "Darwin" -> Mac
        | "Linux" -> Linux
        | _ -> Unknown

let ccopt s = ["-ccopt"; s]
let cclib s = ["-cclib"; s]

let flags =
    match get_os with
    | Windows -> []
                 @ ccopt "-fno-exceptions"
                 @ ccopt "-fno-rtti"
                 @ ccopt "-lstdc++"
    | _ -> []
;;

Configurator.V1.Flags.write_sexp "flags.sexp" flags;
