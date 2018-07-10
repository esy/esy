include EsyLib.Store

module System = EsyLib.System

let%test "Validate padding length on Windows is always 1" = 
    let prefixPath = Fpath.v "test" in
    let padding = getPadding ~system:System.Windows prefixPath in
    match padding with 
        | "_" -> true
        | _ -> false

let%test "Validate padding length on other platforms is not 1" =
    let prefixPath = Fpath.v "test" in
    let padding = getPadding ~system:System.Darwin prefixPath in
    match padding with 
        | "_" -> false
        | _ -> true
