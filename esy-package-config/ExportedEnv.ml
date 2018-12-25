[@@@ocaml.warning "-32"]
type scope =
  | Local
  | Global
  [@@deriving show, ord]

let scope_of_yojson = function
  | `String "global" -> Ok Global
  | `String "local" -> Ok Local
  | _ -> Error "expected either \"local\" or \"global\""

let scope_to_yojson = function
  | Local -> `String "local"
  | Global -> `String "global"

module Item = struct
  type t = {
    value : string [@key "val"];
    scope : (scope [@default Local]);
    exclusive : (bool [@default false]);
  }
  [@@deriving yojson]
end

[@@@ocaml.warning "-32"]
type item = {
  name : string;
  value : string;
  scope : scope;
  exclusive : bool;
}
[@@deriving show, ord]

type t = item StringMap.t
  [@@deriving ord]

let empty = StringMap.empty

let item_of_yojson name json =
  let open Result.Syntax in
  let%bind {Item. value; scope; exclusive} = Item.of_yojson json in
  return ({name; value; scope; exclusive})

let of_yojson = function
  | `Assoc items ->
    let open Result.Syntax in
    let f items (name, json) =
      let%bind item = item_of_yojson name json in
      return (StringMap.add name item items)
    in
    Result.List.foldLeft ~f ~init:StringMap.empty items
  | _ -> Error "expected an object"

let item_to_yojson item =
  `Assoc [
    "val", `String item.value;
    "scope", scope_to_yojson item.scope;
    "exclusive", `Bool item.exclusive;
  ]

let to_yojson env =
  let items =
    let f (name, item) = name, item_to_yojson item in
    List.map ~f (StringMap.bindings env)
  in
  `Assoc items

let pp =
  let ppItem fmt (name, item) =
    Fmt.pf fmt "%s: %a" name pp_item item
  in
  StringMap.pp ~sep:(Fmt.unit ", ") ppItem

let show env = Format.asprintf "%a" pp env

module Override = struct

  type t =
    item StringMap.Override.t
    [@@deriving ord, show]

  let of_yojson = StringMap.Override.of_yojson item_of_yojson
  let to_yojson = StringMap.Override.to_yojson item_to_yojson

end

