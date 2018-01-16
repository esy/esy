include ShellParamExpansionParser

let parse_exn v =
  let lexbuf = Lexing.from_string v in
  read [] `Init lexbuf

let parse v =
  try Ok (parse_exn v)
  with
  | UnmatchedChar (pos, c) ->
    let msg = Printf.sprintf "unknown char: '%c' at position %d" c pos.Lexing.pos_cnum
    in Error msg

type scope = string -> string option

let render ~(scope : scope) v =
  let module Let_syntax = EsyLib.Result.Let_syntax in
  let%bind tokens = parse v in
  let f segments = function
    | String v -> Ok (v::segments)
    | Var (name, default) ->
      begin match scope name, default with
      | Some v, _
      | None, Some v -> Ok (v::segments)
      | _, _ -> Error ("unable to resolve: $" ^ name)
      end
  in
  let%bind segments = EsyLib.Result.listFoldLeft ~f ~init:[] tokens in
  Ok (segments |> List.rev |> String.concat "")
