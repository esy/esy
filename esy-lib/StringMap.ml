include Astring.String.Map

let mergeOverride a b =
  let f _k a b = match (a, b) with
  | Some a, None -> Some a
  | Some _, Some b
  | None, Some b -> Some b
  | None, None -> None
  in
  merge f a b
