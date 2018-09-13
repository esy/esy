type t = Yojson.Safe.json
type json = t

type 'a encoder = 'a -> t
type 'a decoder = t -> ('a, string) result

let to_yojson x = x
let of_yojson x = Ok x

let pp = Yojson.Safe.pretty_print

let parseJsonWith parser json =
  Run.ofStringError (parser json)

let parseStringWith parser data =
  let json = Yojson.Safe.from_string data in
  parseJsonWith parser json

let mergeAssoc items update =
  let toMap items =
    let f map (name, json) = StringMap.add name json map in
    List.fold_left ~f ~init:StringMap.empty items
  in
  let items = toMap items in
  let update = toMap update in
  let result = StringMap.mergeOverride items update in
  StringMap.bindings result

module Encode = struct

  let string x = `String x
  let list encode xs =
    `List (List.map ~f:encode xs)
end

module Decode = struct

  let string (json : t) =
    match json with
    | `String v -> Ok v
    | _ -> Error "expected string"

  let assoc (json : t) =
    match json with
    | `Assoc v -> Ok v
    | _ -> Error "expected object"

  let extractField ~name (json : t) =
    match json with
    | `Assoc items ->
      begin match List.find_opt ~f:(fun (k, _v) -> k = name) items with
      | Some (_, v) -> Ok v
      | None -> Error ("no such field: " ^ name)
      end
    | _ -> Error "expected object"

  let extractFieldOpt ~name (json : t) =
    match json with
    | `Assoc items ->
      begin match List.find_opt ~f:(fun (k, _v) -> k = name) items with
      | Some (_, v) -> Ok (Some v)
      | None -> Ok None
      end
    | _ -> Error "expected object"

  let field ~name parse json =
    match extractField ~name json with
    | Ok v -> parse v
    | Error err -> Error err

  let fieldOpt ~name parse json =
    match extractFieldOpt ~name json with
    | Ok (Some v) ->
      begin match parse v with
      | Ok v -> Ok (Some v)
      | Error err -> Error err
      end
    | Ok None -> Ok None
    | Error err -> Error err

  let list ?(errorMsg="expected an array") value (json : t) =
    match json with
    | `List (items : t list) ->
      let f acc v = match acc, (value v) with
        | Ok acc, Ok v -> Ok (v::acc)
        | Ok _, Error err -> Error err
        | err, _ -> err
      in begin
      match List.fold_left ~f ~init:(Ok []) items with
      | Ok items -> Ok (List.rev items)
      | error -> error
      end
    | _ -> Error errorMsg

  let stringMap ?(errorMsg= "expected an object") value (json : t) =
    match json with
    | `Assoc items ->
      let f acc (k, v) = match acc, k, (value v) with
        | Ok acc, k, Ok v -> Ok (StringMap.add k v acc)
        | Ok _, _, Error err -> Error err
        | err, _, _ -> err
      in
      List.fold_left ~f ~init:(Ok StringMap.empty) items
    | _ -> Error errorMsg

  let return v _json = Ok v

  let map f decoder json =
    match decoder json with
    | Ok v -> Ok (f v)
    | Error err -> Error err

  let app f decoder json =
    match f json with
    | Ok f ->
      begin match decoder json with
      | Ok v -> Ok (f v)
      | Error err -> Error err
      end
    | Error err -> Error err

  let (<$>) = map
  let (<*>) = app

end

module Edit = struct

  type t = (loc, string) result

  and loc =
    | AtRoot of fields
    | AtAssoc of {
        up : loc;
        left : fields;
        current : field;
        right : fields;
      }

  and fields = field list
  and field = string * json

  let ofJson json =
    match json with
    | `Assoc fields -> Ok (AtRoot fields)
    | _ -> Error "expected object at root"

  let diff name fields =
    let rec diff' left right =
      match right with
      | [] -> (left, (name, `Assoc []), right)
      | (n, v)::right ->
        if n = name
        then (left, (n, v), right)
        else diff' ((n, v)::left) right
    in
    diff' [] fields

  let get name editor =
    let open Result.Syntax in
    let%bind editor = editor in
    match editor with
    | AtRoot fields ->
      let left, current, right = diff name fields in
      Ok (AtAssoc {left; current; right; up = editor})
    | AtAssoc {current = (_k, json); _} ->
      let%bind fields = Decode.assoc json in
      let left, current, right = diff name fields in
      Ok (AtAssoc {left; current; right; up = editor})

  let update v editor =
    let open Result.Syntax in
    let%bind editor = editor in
    match editor with
    | AtRoot _ -> Error "can't update root"
    | AtAssoc loc ->
      let k, _ = loc.current in
      Ok (AtAssoc {loc with current = k, v;})

  let build editor =
    match editor with
    | AtRoot fields -> fields
    | AtAssoc loc ->
      let fields =
        let f right field = field::right in
        List.fold_left ~f ~init:(loc.current::loc.right) loc.left
      in
      fields

  let up editor =
    let open Result.Syntax in
    let%bind editor = editor in
    match editor with
    | AtRoot _ -> Error "can't go up from the root"
    | AtAssoc {up = AtRoot _; _} -> Ok (AtRoot (build editor))
    | AtAssoc {up = AtAssoc up; _} ->
      let k, _ = up.current in
      let v = `Assoc (build editor) in
      Ok (AtAssoc {up with current = k, v;})

  let set name v editor =
    editor |> get name |> update v |> up

  let commit editor =
    let open Result.Syntax in
    let%bind editor = editor in
    let rec commit' editor =
      match editor with
      | AtRoot fields -> Ok (`Assoc fields)
      | AtAssoc {up = AtRoot _; _} -> commit' (AtRoot (build editor))
      | AtAssoc {up = AtAssoc up; _} ->
        let k, _ = up.current in
        let v = `Assoc (build editor) in
        commit' (AtAssoc {up with current = k, v;})
    in
    commit' editor
end
