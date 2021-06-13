include Set.Make(String);

let to_yojson = set => Json.Encode.(list(string))(elements(set));

let of_yojson = json => {
  open Result.Syntax;
  let* elements = Json.Decode.(list(string))(json);
  Ok(of_list(elements));
};
