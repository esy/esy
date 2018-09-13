type t = Yojson.Safe.json

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

module Decode = struct

  let string (json : t) =
    match json with
    | `String v -> Ok v
    | _ -> Error "expected string"

  let assoc (json : t) =
    match json with
    | `Assoc v -> Ok v
    | _ -> Error "expected object"

  let field ~name (json : t) =
    match json with
    | `Assoc items ->
      begin match List.find_opt ~f:(fun (k, _v) -> k = name) items with
      | Some (_, v) -> Ok v
      | None -> Error ("no such field: " ^ name)
      end
    | _ -> Error "expected object"

  let fieldOpt ~name (json : t) =
    match json with
    | `Assoc items ->
      begin match List.find_opt ~f:(fun (k, _v) -> k = name) items with
      | Some (_, v) -> Ok (Some v)
      | None -> Ok None
      end
    | _ -> Error "expected object"

  let fieldWith ~name parse json =
    match field ~name json with
    | Ok v -> parse v
    | Error err -> Error err

  let fieldOptWith ~name parse json =
    match fieldOpt ~name json with
    | Ok (Some v) -> parse v
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

end
