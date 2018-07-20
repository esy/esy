include EsyLib.Store

module System = EsyLib.System

let%test "Validate padding length on Windows is always 1" = 
    let prefixPath = Fpath.v "test" in
    let padding = getPadding ~system:System.Platform.Windows prefixPath in
    match padding with 
        | Ok("_") -> true
        | _ -> false

let%test "Validate padding length on other platforms is not 1" =
    let prefixPath = Fpath.v "test" in
    let padding = getPadding ~system:System.Platform.Darwin prefixPath in
    match padding with 
        | Ok("_") -> false
        | Error(_) -> false
        | _ -> true

let%test "Validate an error is given if the path is too long" =
    let superLongPath = String.make 260 'a' in
    let prefixPath = Fpath.v superLongPath in
    let padding = getPadding ~system:System.Platform.Darwin prefixPath in
    match padding with
        | Error(_) -> true
        | _ -> false
