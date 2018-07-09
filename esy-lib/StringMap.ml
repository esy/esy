include Astring.String.Map

let mergeOverride a b =
  let f _k a b = match (a, b) with
  | Some a, None -> Some a
  | Some _, Some b
  | None, Some b -> Some b
  | None, None -> None
  in
  merge f a b

let values map =
  let f _k v vs = v::vs in
  fold f map []

let keys map =
  let f k _v ks = k::ks in
  fold f map []

let to_yojson v_to_yojson map =
  let items =
    let f k v items = (k, v_to_yojson v)::items in
    fold f map []
  in
  `Assoc items

let of_yojson v_of_yojson =
  let open Result.Syntax in
  function
  | `Assoc items ->
    let f items (k, json) =
      let%bind v = v_of_yojson json in
      return (add k v items)
    in
    Result.List.foldLeft ~f ~init:empty items
  | _ -> Error "expected an object"
