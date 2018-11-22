
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
    Fmt.pf fmt "@[<h 2>%s@\n%a@]" filename Fmt.text out

let ppContext fmt context =
  Fmt.(list ~sep:(unit "@\n") ppContextItem) fmt (List.rev context)

let ppError fmt (msg, context) =
  Fmt.pf fmt "@[<v 2>@[<h>error: %a@]@\n%a@]" Fmt.text msg ppContext context

let return v =
  Ok v

let error msg =
  Error (msg, [])

let errorf fmt =
  let kerr _ = Error (Format.flush_str_formatter (), []) in
  Format.kfprintf kerr Format.str_formatter fmt

let context v line =
  match v with
  | Ok v -> Ok v
  | Error (msg, context) -> Error (msg, (Line line)::context)

let contextf v fmt =
  let kerr _ = context v (Format.flush_str_formatter ()) in
  Format.kfprintf kerr Format.str_formatter fmt

let bind ~f v = match v with
  | Ok v -> f v
  | Error err -> Error err

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
  | Error (`CommandError (cmd, status)) ->
    let line = Format.asprintf
      "command %a exited with status %a"
      Bos.Cmd.pp cmd Bos.OS.Cmd.pp_status status
    in
    Error (line, [])

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

module Syntax = struct
  let return = return
  let error = error
  let errorf = errorf
  module Let_syntax = struct
    let bind = bind
  end
end

module List = struct

  let foldLeft ~f ~init xs =
    let rec fold acc xs =  match acc, xs with
      | Error err, _ -> Error err
      | Ok acc, [] -> Ok acc
      | Ok acc, x::xs -> fold (f acc x) xs
    in
    fold (Ok init) xs

  let waitAll xs =
    let rec _waitAll xs = match xs with
      | [] -> return ()
      | x::xs ->
        let f () = _waitAll xs in
        bind ~f x
    in
    _waitAll xs

  let mapAndWait ~f xs =
    waitAll (List.map ~f xs)

end
