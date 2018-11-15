type t = {
  prefixPath : Path.t option;
} [@@deriving (show)]

let empty = {
  prefixPath = None;
}

let ofPath path =
  let open RunAsync.Syntax in

  let ofFilename filename =
    let%bind data = Fs.readFile filename in
    let%bind ast = RunAsync.ofStringError (EsyYarnLockfile.parse data) in
    match ast with
    | EsyYarnLockfile.Mapping items ->
      let f acc item =
        let open Result.Syntax in
        match item with
        | "esy-prefix-path", EsyYarnLockfile.String value ->
          let%bind value = Path.ofString value in
          let value =
            if Path.isAbs value
            then value
            else Path.(normalize (append path value))
          in
          return {prefixPath = Some value;}
        | "esy-prefix-path", _ ->
          error (`Msg "esy-prefix-path should be a string")
        | _ ->
          return acc
      in
      begin
      match Result.List.foldLeft ~init:empty ~f items with
      | Ok esyRc -> return esyRc
      | v -> v |> Run.ofBosError |> RunAsync.ofRun
      end
    | _ -> error "expected mapping"
  in
  let filename = Path.(path / ".esyrc") in
  if%bind Fs.exists filename
  then ofFilename filename
  else return empty
