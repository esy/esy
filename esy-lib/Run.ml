
(**
 * Computation with structured error reporting.
 *)
type 'a t = ('a, error) result
and error = string * context
and context = contextItem list
and contextItem =
  | Line of string
  | LogOutput of (string * string)

let ppContextItem fmt = function
  | Line line ->
    Fmt.pf fmt "@[<h>%s@]" line
  | LogOutput (filename, out) ->
    Fmt.pf fmt "@[<v 2>%s@\n%a@]" filename Fmt.text out

let ppContext = Fmt.(list ~sep:(unit "@\n") ppContextItem)

let ppError fmt (msg, context) =
  Fmt.pf fmt "@[<v 2>%s@\n%a@]" msg ppContext context

let return v =
  Ok v

let error msg =
  Error (msg, [])

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
  | Error (msg, context) -> Error (msg, (Line line)::context)

let withContextOfLog ?(header="Log output:") content v =
  match v with
  | Ok v -> Ok v
  | Error (msg, context) ->
    let item = LogOutput (header, content) in
    Error (msg, item::context)

let formatError error =
  Format.asprintf "%a" ppError error

let ofStringError v =
  match v with
  | Ok v -> Ok v
  | Error line -> Error (line, [])

let ofBosError v =
  match v with
  | Ok v -> Ok v
  | Error (`Msg line) -> Error (line, [])

let ofOption ?err = function
  | Some v -> return v
  | None ->
    let err = match err with
    | Some err -> err
    | None -> "not found"
    in error err

let toResult = function
  | Ok v -> Ok v
  | Error err -> Error (formatError err)

let runExn ?err = function
  | Ok v -> v
  | Error (msg, ctx) ->
    let msg = match err with
    | Some err -> err ^ ": " ^ msg
    | None -> msg
    in
    failwith (formatError (msg, ctx))

module List = struct

  let foldLeft ~f ~init xs =
    let rec fold acc xs =  match acc, xs with
      | Error err, _ -> Error err
      | Ok acc, [] -> Ok acc
      | Ok acc, x::xs -> fold (f acc x) xs
    in
    fold (Ok init) xs

end
