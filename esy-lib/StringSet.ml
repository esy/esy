include Set.Make(String)

let to_yojson set =
  Json.Encode.(list string) (elements set)

let of_yojson json =
  let open Result.Syntax in
  let%bind elements = Json.Decode.(list string) json in
  Ok (of_list elements)
