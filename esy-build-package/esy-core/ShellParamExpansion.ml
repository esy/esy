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
