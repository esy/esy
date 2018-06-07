
(**
 * Computation with structured error reporting.
 *)
type 'a t = ('a, error) result
and error = string * context
and context = contextItem list
and contextItem =
  | Line of string
  | LogOutput of (string * string)

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

let formatError (msg, context) =
  let rec formatContext result = function
  | [] -> result
  | (Line msg)::context ->
    let result = (Printf.sprintf "  While %s" msg)::result in
    formatContext result context
  | (LogOutput (header, content))::context ->
    let lines =
      content
      |> String.split_on_char '\n'
      |> List.map (fun line -> "    " ^ line)
    in
    let lines =
      ("  " ^ header)::lines
      |> String.concat "\n"
    in
    formatContext (lines::result) context
  in
  match formatContext [] context with
  | [] -> Printf.sprintf "Error: %s" msg
  | context -> Printf.sprintf "Error: %s\n%s" msg (String.concat "\n" context)

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
