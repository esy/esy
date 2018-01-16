
(**
 * Computation with structured error reporting.
 *)
type 'a t = ('a, error) result
and error = string list

let return v =
  Ok v

let error msg =
  Error [msg]

module Syntax = struct
  let return = return
  let error = error
  module Let_syntax = EsyLib.Result.Let_syntax
end

let withContext line v =
  match v with
  | Ok v -> Ok v
  | Error lines -> Error (line::lines)

let formatError lines = match List.rev lines with
  | [] -> "Error"
  | error::[] -> "Error: " ^ error
  | error::context ->
    let context = List.map (fun line -> "  " ^ line) context in
    String.concat "\n" (("Error: " ^ error)::context)

let liftOfSingleLineError v =
  match v with
  | Ok v -> Ok v
  | Error line -> Error [line]

let foldLeft ~f ~init xs =
  let rec fold acc xs =  match acc, xs with
    | Error err, _ -> Error err
    | Ok acc, [] -> Ok acc
    | Ok acc, x::xs -> fold (f acc x) xs
  in
  fold (Ok init) xs
