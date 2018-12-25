[@@@ocaml.warning "-32"]
type t =
  | Parsed of string list
  | Unparsed of string
  [@@deriving show, ord]

let of_yojson (json : Json.t) =
  match json with
  | `String command -> Ok (Unparsed command)
  | `List command ->
    begin match Json.Decode.(list string (`List command)) with
    | Ok args -> Ok (Parsed args)
    | Error err -> Error err
    end
  | _ -> Error "expected either a string or an array of strings"

let to_yojson v =
  match v with
  | Parsed args -> `List (List.map ~f:(fun arg -> `String arg) args)
  | Unparsed line -> `String line
