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

type 'a stringMap = 'a t
let compare_stringMap = compare

module Override : sig
  type 'a t =
    'a override stringMap

  and 'a override =
    | Drop
    | Edit of 'a

  val apply : 'a stringMap -> 'a t -> 'a stringMap

  val compare : ('a -> 'a -> int) -> 'a t -> 'a t -> int

  val of_yojson :
    (string -> Yojson.Safe.json -> ('a, string) result)
    -> Yojson.Safe.json -> ('a t, string) result

  val to_yojson :
    ('a -> Yojson.Safe.json)
    -> 'a t -> Yojson.Safe.json

  val pp : 'a Fmt.t -> 'a t Fmt.t

end = struct

  type 'a t =
    'a override stringMap
    [@@deriving ord]

  and 'a override =
    | Drop
    | Edit of 'a

  let apply map override =
    let map =
      let f name override map =
        match override with
        | Drop -> remove name map
        | Edit value -> add name value map
      in
      fold f override map
    in
    map

  let of_yojson value_of_yojson = function
    | `Assoc items ->
      let open Result.Syntax in
      let f map (name, json) =
        match json with
        | `Null ->
          let override = Drop in
          return (add name override map)
        | _ ->
          let%bind value = value_of_yojson name json in
          let override = Edit value in
          return (add name override map)
      in
      Result.List.foldLeft ~f ~init:empty items
    | _ -> Error "expected an object"

  let to_yojson value_to_yojson env =
    let items =
      let f (name, override) =
        match override with
        | Edit value ->
          name, value_to_yojson value
        | Drop ->
          name, `Null
      in
      List.map ~f (bindings env)
    in
    `Assoc items

  let pp pp_value =
    let ppOverride fmt override =
      match override with
      | Drop -> Fmt.unit "remove" fmt ()
      | Edit v -> pp_value fmt v
    in
    let ppItem = Fmt.(pair ~sep:(unit ": ") string ppOverride) in
    Fmt.braces (pp ~sep:(Fmt.unit ", ") ppItem)

  let%test "apply: add key" =
    let orig = empty |> add "a" "b" in
    let override = empty |> add "c" (Edit "d") in
    let result = apply orig override in
    let expect = empty |> add "a" "b" |> add "c" "d" in
    compare_stringMap String.compare result expect = 0

  let%test "apply: drop key" =
    let orig = empty |> add "a" "b" |> add "c" "d" in
    let override = empty |> add "c" Drop in
    let result = apply orig override in
    let expect = empty |> add "a" "b" in
    compare_stringMap String.compare result expect = 0

  let%test "apply: replace key" =
    let orig = empty |> add "a" "b" |> add "c" "d" in
    let override = empty |> add "c" (Edit "d!") in
    let result = apply orig override in
    let expect = empty |> add "a" "b" |> add "c" "d!" in
    compare_stringMap String.compare result expect = 0

end
