type t = Resolution.t StringMap.t

let empty = StringMap.empty

let find resolutions name =
  StringMap.find_opt name resolutions

let add name resolution resolutions =
  StringMap.add name {Resolution.name; resolution} resolutions

let entries = StringMap.values

let digest resolutions =
  let f _ resolution digest = Digestv.(digest + Resolution.digest resolution) in
  StringMap.fold f resolutions Digestv.empty

let to_yojson v =
  let items =
    let f name {Resolution. resolution; _} items =
      (name, Resolution.resolution_to_yojson resolution)::items
    in
    StringMap.fold f v []
  in
  `Assoc items

let of_yojson =
  let open Result.Syntax in
  let parseKey k =
    match PackagePath.parse k with
    | Ok ((_path, name)) -> Ok name
    | Error err -> Error err
  in
  let parseValue name json =
    match json with
    | `String v ->
      let%bind version =
        match Astring.String.cut ~sep:"/" name with
        | Some ("@opam", _) -> Version.parse ~tryAsOpam:true v
        | _ -> Version.parse v
      in
      return {Resolution. name; resolution = Resolution.Version version;}
    | `Assoc _ ->
      let%bind resolution = Resolution.resolution_of_yojson json in
      return {Resolution. name; resolution;}
    | _ -> Error "expected string"
  in
  function
  | `Assoc items ->
    let f res (key, json) =
      let%bind key = parseKey key in
      let%bind value = parseValue key json in
      Ok (StringMap.add key value res)
    in
    Result.List.foldLeft ~f ~init:empty items
  | _ -> Error "expected object"
