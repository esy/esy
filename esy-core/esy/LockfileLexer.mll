{
include LockfileLexerSupport
}

let digit   = ['0'-'9']
let frac    = '.' digit*
let exp     = ['e' 'E'] ['-' '+']? digit+
let float   = digit* frac? exp?

let ws      = '\t' | ' '
let newline = '\r' | '\n' | "\r\n"
let id      = ['a'-'z' 'A'-'Z' '_'] ['a'-'z' 'A'-'Z' '0'-'9' '_']*

rule read =
  parse
  | newline  { NEWLINE }
  | ws       { read lexbuf }
  | float    { NUMBER (float_of_string (Lexing.lexeme lexbuf)) }
  | "true"   { TRUE }
  | "false"  { FALSE }
  | id       { IDENTIFIER (Lexing.lexeme lexbuf) }
  | '"'      { read_string (Buffer.create 16) lexbuf }
  | ':'      { COLON }
  | ','      { COMMA }
  | _        {
      let msg = Printf.sprintf "Unexpected char: '%s'" (Lexing.lexeme lexbuf) in
      raise (SyntaxError msg)
    }
  | eof      { EOF }

and read_string buf =
  parse
  | '"'       { STRING (Buffer.contents buf) }
  | '\\' '/'  { Buffer.add_char buf '/'; read_string buf lexbuf }
  | '\\' '\\' { Buffer.add_char buf '\\'; read_string buf lexbuf }
  | '\\' 'b'  { Buffer.add_char buf '\b'; read_string buf lexbuf }
  | '\\' 'f'  { Buffer.add_char buf '\012'; read_string buf lexbuf }
  | '\\' 'n'  { Buffer.add_char buf '\n'; read_string buf lexbuf }
  | '\\' 'r'  { Buffer.add_char buf '\r'; read_string buf lexbuf }
  | '\\' 't'  { Buffer.add_char buf '\t'; read_string buf lexbuf }
  | [^ '"' '\\']+
    { Buffer.add_string buf (Lexing.lexeme lexbuf);
      read_string buf lexbuf
    }
  | _ { raise (SyntaxError ("Illegal string character: " ^ Lexing.lexeme lexbuf)) }
  | eof { raise (SyntaxError ("String is not terminated")) }
