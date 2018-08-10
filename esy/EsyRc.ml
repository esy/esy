module P = LockfileParser

type t =
  { prefixPath : Path.t option }
  [@@deriving (show)]

let empty = {prefixPath = None}

let ofPath path =
  let open RunAsync.Syntax in

  let ofFilename filename =
    let%bind data = Fs.readFile filename in
    let%bind ast = RunAsync.ofRun (P.parse data) in
    match ast with
    | P.Mapping items ->
      let f acc item =
        match acc, item with
        | Ok { prefixPath = None }, ("esy-prefix-path", P.String value) ->
          let open Result.Syntax in
          let%bind value = Path.ofString value in
          let value = if Path.isAbs value
            then value
            else Path.(value |> (append path) |> normalize)
          in
          Ok {prefixPath = Some value}
        | Ok _, ("esy-prefix-path", _) ->
          Error (`Msg "\"esy-prefix-path\" should be a string")
        | _, _ ->
          acc
      in
      begin
      match List.fold_left ~init:(Ok { prefixPath = None }) ~f items with
      | Ok esyRc -> return esyRc
      | v -> v |> Run.ofBosError |> RunAsync.ofRun
      end
    | _ -> error "expected mapping"
  in
  let filename = Path.(path / ".esyrc") in
  if%bind Fs.exists filename
  then ofFilename filename
  else return empty
