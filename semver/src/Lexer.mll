{

  exception Error of string

  let unexpected lexbuf =
    raise (Error ("Unexpected char: " ^ Lexing.lexeme lexbuf))

  open Parser

}

let n = ['0' - '9']+
let a = ['a' - 'u'] | ['w' - 'z'] | ['A'-'Z'] (* exclude 'v' from here *)
let an = a | n
let ws = ' '

rule tokenize = parse
  | '^' { CARET }
  | '~' { TILDA }
  | '.' { DOT }
  | '-' { MINUS }
  | '+' { PLUS }
  | '*' { STAR }
  | 'v' { V "v" }
  | 'x' { X "x" }
  | 'X' { X "X" }
  | '>' ws* { GT }
  | '<' ws* { LT }
  | '>' '=' ws* { GTE }
  | '<' '=' ws* { LTE }
  | '=' ws* { EQ }
  | ws+ '-' ws+ { DASH }
  | ws* '|' '|' ws* { OR }
  | ws+ { AND }
  | n+ as v { NUM v }
  | an+ as v { WORD v }
  | eof { EOF }
  | _ { unexpected lexbuf }
