{

  exception Error of string

  let unexpected lexbuf =
    raise (Error ("Unexpected char: " ^ Lexing.lexeme lexbuf))

  open Parser

}

let n = ['0' - '9']
let a = ['a' - 'z'] | ['A'-'Z']
let an = a | n

rule version = parse
  | n+ as v { NUM v }
  | an+ as v { ALNUM v }
  | '.' { DOT }
  | '-' { MINUS }
  | '+' { PLUS }
  | eof { EOF }
  | _ { unexpected lexbuf }
