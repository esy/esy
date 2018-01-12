include CommandExprParser

let parse v =
  let lexbuf = Lexing.from_string v in
  Ok (read [] lexbuf)
