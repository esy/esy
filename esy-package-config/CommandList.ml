[@@@ocaml.warning "-32"]
type t =
  Command.t list
  [@@deriving show, ord]

let empty = []

let of_yojson (json : Json.t) =
  let open Result.Syntax in
  match json with
  | `Null -> return []
  | `List commands ->
    Json.Decode.list Command.of_yojson (`List commands)
  | `String command ->
    let%bind command = Command.of_yojson (`String command) in
    return [command]
  | _ -> Error "expected either a null, a string or an array"

let to_yojson commands = `List (List.map ~f:Command.to_yojson commands)
