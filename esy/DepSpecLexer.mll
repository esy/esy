{
exception Error of string
}

let id          = ['a'-'z' 'A'-'Z' '_'] ['a'-'z' 'A'-'Z' '0'-'9' '_']*
let space       = [ ' ' '\t' ]+

rule read = parse
 | space        { read lexbuf }
 | id as id     { DepSpecParser.ID id }
 | '('          { DepSpecParser.LPAREN }
 | ')'          { DepSpecParser.RPAREN }
 | '+'          { DepSpecParser.PLUS }
 | eof          { DepSpecParser.EOF }
 | _ as c       { raise (Error (Printf.sprintf "unexpected char: %c" c)) }
