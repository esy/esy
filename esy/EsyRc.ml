type t = {
  prefixPath : Path.t option;
} [@@deriving of_yojson]

let empty = {
  prefixPath = None;
}

let ofPath path =
  let open RunAsync.Syntax in

  let normalizePath p =
    if Path.isAbs p
    then p
    else Path.(normalize (path // p))
  in

  let ofFile filename =
    let%bind data = Fs.readFile filename in
    let%bind json =
      match Json.parse data with
      | Ok json -> return json
      | Error err ->
        errorf
          "expected %a to be a JSON file but got error: %a"
          Path.pp filename Run.ppError err
    in
    let%bind rc = RunAsync.ofStringError (of_yojson json) in
    let rc = {
      prefixPath = Option.map ~f:normalizePath rc.prefixPath;
    } in
    return rc;
  in

  let filename = Path.(path / ".esyrc") in

  if%bind Fs.exists filename
  then ofFile filename
  else return empty
