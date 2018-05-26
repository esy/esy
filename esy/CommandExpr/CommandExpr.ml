include CommandExprTypes

module V = Value
module E = Expr

let parse src =
  let tokensStore = ref None in
  let getToken lexbuf =
    let tokens =
      match !tokensStore with
      | Some tokens -> tokens
      | None -> CommandExprLexer.read [] lexbuf
    in
    match tokens with
    | tok::rest ->
      tokensStore := Some rest;
      tok
    | [] -> CommandExprParser.EOF
  in
  let lexbuf = Lexing.from_string src in
  let open Run.Syntax in
  try
    return (CommandExprParser.start getToken lexbuf)
  with
  | Failure v ->
    Run.error v
  | CommandExprParser.Error ->
    error "Syntax error"
  | CommandExprLexer.Error (pos, msg) ->
    let cnum = pos.Lexing.pos_cnum - 1 in
    let msg = ParseUtil.formatParseError ~src ~cnum msg in
    error msg

let formatName = function
  | Some namespace, name -> namespace ^ "." ^ name
  | None, name -> name

let eval ~pathSep ~colon ~scope string =
  let open Run.Syntax in
  let%bind expr = parse string in

  let lookupValue name = match scope name with
  | Some value -> return value
  | None ->
    let name = formatName name in
    let msg = Printf.sprintf "Undefined variable '%s'" name in
    error msg
  in

  let rec evalToString expr =
    match%bind eval expr with
    | V.String v -> return v
    | V.Bool _ -> error "Expected string but got bool"

  and evalToBool expr =
    match%bind eval expr with
    | V.Bool v -> return v
    | V.String _ -> error "Expected bool but got string"

  and eval = function
    | E.String s -> return (V.String s)
    | E.PathSep -> return (V.String pathSep)
    | E.Colon -> return (V.String colon)
    | E.EnvVar name -> return (V.String ("$" ^ name))
    | E.Var name -> lookupValue name
    | E.Condition (cond, t, e) ->
      if%bind evalToBool cond
      then eval t
      else eval e
    | E.And (a, b) ->
      let%bind a = evalToBool a in
      let%bind b = evalToBool b in
      return (V.Bool (a && b))
    | E.Concat exprs ->
      let f s expr =
        let%bind v = evalToString expr in
        return (s ^ v)
      in
      let%bind v = Run.List.foldLeft ~f ~init:"" exprs in
      return (V.String v)
  in
  eval expr

let render ?(pathSep="/") ?(colon=":") ~(scope : scope) (string : string) =
  let open Run.Syntax in
  match%bind eval ~pathSep ~colon ~scope string with
  | V.String v -> return v
  | V.Bool _ -> error "expected string"
