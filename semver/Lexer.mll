{

  exception Error of string

  let unexpected lexbuf =
    raise (Error ("Unexpected char: " ^ Lexing.lexeme lexbuf))

  open Parser

}

let n = ['0' - '9']
let a = ['a' - 'z'] | ['A'-'Z']
let an = a | n
let ws = ' '*

rule tokenize = parse
  | '^' { CARET }
  | '~' { TILDA }
  | '.' { DOT }
  | '-' { MINUS }
  | ws+ '-' ws+ { DASH }
  | '+' { PLUS }
  | '*' { STAR }
  | 'x' { X "x" }
  | 'X' { X "X" }
  | '>' { GT }
  | '<' { LT }
  | '>' '=' { GTE }
  | '<' '=' { LTE }
  | '=' { EQ }
  | ws '|' '|' ws { OR }
  | n+ as v { NUM v }
  | an+ as v { ALNUM v }
  | ws { WS }
  | eof { EOF }
  | _ { unexpected lexbuf }
