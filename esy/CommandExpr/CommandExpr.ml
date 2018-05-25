open Std

include CommandExprParser

let parse_exn v =
  let lexbuf = Lexing.from_string v in
  read [] lexbuf

let parse src =
  try Ok (parse_exn src)
  with
  | Failure v ->
    Run.error v
  | UnmatchedChar (pos, chr) ->
    let cnum = pos.Lexing.pos_cnum - 1 in
    let msg = Printf.sprintf "unmatched character: %c" chr in
    let msg = ParseUtil.formatParseError ~src ~cnum msg in
    Run.error msg
  | UnmatchedVarBrace (pos, ()) ->
    let cnum = pos.Lexing.pos_cnum - 1 in
    let msg = ParseUtil.formatParseError ~src ~cnum "unmatched brace: {" in
    Run.error msg

type scope = name -> value option
and value = string

let render ?(pathSep="/") ?(colon=":") ~(scope : scope) (string : string) =
  let open Run.Syntax in

  let lookup name = match scope name with
  | Some value -> Ok value
  | None ->
    let name = String.concat "." name in
    let msg = Printf.sprintf "Undefined variable '%s'" name in
    Run.error msg
  in

  let renderExpr tokens =
    let f segments = function
    | Var name -> let%bind v = lookup name in Ok (v::segments)
    | EnvVar name -> let v = "$" ^ name in Ok (v::segments)
    | Literal v -> Ok (v::segments)
    | Colon -> Ok (colon::segments)
    | PathSep -> Ok (pathSep::segments)
    in
    let%bind segments = Result.listFoldLeft ~f ~init:[] tokens in
    Ok (segments |> List.rev |> String.concat "")
  in

  let%bind tokens = parse string in
  let f segments (tok : token) =
    match tok with
    | String v -> Ok(v::segments)
    | Expr tokens -> let%bind v = renderExpr tokens in Ok (v::segments)
  in
  let%bind segments = Result.listFoldLeft ~f ~init:[] tokens in
  Ok (segments |> List.rev |> String.concat "")
