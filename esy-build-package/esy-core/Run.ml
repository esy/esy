
(**
 * Computation with structured error reporting.
 *)
type 'a t = ('a, error) result
and error = string list

let return v =
  Ok v

let error msg =
  Error [msg]

let bind ~f v = match v with
  | Ok v -> f v
  | Error err -> Error err

module Syntax = struct
  let return = return
  let error = error
  module Let_syntax = struct
    let bind = bind
  end
end

let withContext line v =
  match v with
  | Ok v -> Ok v
  | Error lines -> Error (line::lines)

let formatError lines = match List.rev lines with
  | [] -> "Error"
  | error::[] -> "Error: " ^ error
  | error::context ->
    let context = List.map (fun line -> "  While " ^ line) context in
    String.concat "\n" (("Error: " ^ error)::context)

let liftOfStringError v =
  match v with
  | Ok v -> Ok v
  | Error line -> Error [line]

let liftOfBosError v =
  match v with
  | Ok v -> Ok v
  | Error (`Msg line) -> Error [line]

let foldLeft ~f ~init xs =
  let rec fold acc xs =  match acc, xs with
    | Error err, _ -> Error err
    | Ok acc, [] -> Ok acc
    | Ok acc, x::xs -> fold (f acc x) xs
  in
  fold (Ok init) xs

let rec waitAll = function
  | [] -> return ()
  | x::xs ->
    let f () = waitAll xs in
    bind ~f x
