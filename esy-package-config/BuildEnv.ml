[@@@ocaml.warning "-32"]
type item = {
  name : string;
  value : string;
}
[@@deriving show, ord]

type t =
  item StringMap.t
  [@@deriving ord]

let empty = StringMap.empty

let item_of_yojson name json =
  match json with
  | `String value -> Ok {name; value;}
  | _ -> Error "expected string"

let of_yojson =
  let open Result.Syntax in
  function
  | `Assoc items ->
    let f items (name, json) =
      let%bind item = item_of_yojson name json in
      return (StringMap.add name item items)
    in
    Result.List.foldLeft ~f ~init:StringMap.empty items
  | _ -> Error "expected object"

let item_to_yojson {value;_} = `String value

let to_yojson env =
  let items =
    let f (name, item) = name, item_to_yojson item in
    List.map ~f (StringMap.bindings env)
  in
  `Assoc items

let pp =
  let ppItem fmt (name, {value;_}) =
    Fmt.pf fmt "%s: %s" name value
  in
  StringMap.pp ~sep:(Fmt.unit ", ") ppItem

let show env = Format.asprintf "%a" pp env

module Override = struct
  type t = item StringMap.Override.t [@@deriving ord, show]
  let of_yojson = StringMap.Override.of_yojson item_of_yojson
  let to_yojson = StringMap.Override.to_yojson item_to_yojson
end
