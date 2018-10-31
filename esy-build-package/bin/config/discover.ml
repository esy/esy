
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

let c_flags = ["-I";  "./../../../include"; "-I"; "./../../../src"]

let ccopt s = ["-ccopt"; s]
let cclib s = ["-cclib"; s]

let flags =
    match get_os with
    | Windows ->  []
        @ ccopt("-L.")
        @ ccopt("-L./../../lib-mingw-w64")
        @ cclib("-lglfw3")
        @ cclib("-lgdi32")
    | Linux -> []
        @ ccopt("-L.")
        @ ccopt("-L./../glfw/src")
        @ cclib("-lGL")
        @ cclib("-lGLU")
        @ cclib("-lglfw3")
        @ cclib("-lX11")
        @ cclib("-lXxf86vm")
        @ cclib("-lXrandr")
        @ cclib("-lpthread")
        @ cclib("-lXi")
    | _ -> []
        @ ccopt("-L.")
        @ ccopt("-L./../glfw/src")
        @ cclib("-lglfw3")
        @ ccopt("-framework OpenGL")
        @ ccopt("-framework Cocoa")
        @ ccopt("-framework IOKit")
        @ ccopt("-framework CoreVideo")
;;

let cxx_flags =
    match get_os with
    | Windows -> c_flags @ ["-fno-exceptions"; "-fno-rtti"; "-lstdc++"]
    | _ -> c_flags
;;

Configurator.V1.Flags.write_sexp "c_flags.sexp" c_flags;
Configurator.V1.Flags.write_sexp "cxx_flags.sexp" cxx_flags;
Configurator.V1.Flags.write_sexp "flags.sexp" flags;
