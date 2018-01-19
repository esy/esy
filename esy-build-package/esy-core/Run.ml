
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

let liftOfStringError v =
  match v with
  | Ok v -> Ok v
  | Error line -> Error (line, [])

let liftOfBosError v =
  match v with
  | Ok v -> Ok v
  | Error (`Msg line) -> Error (line, [])

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
