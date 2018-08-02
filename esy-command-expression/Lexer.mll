{

open Parser

exception Error of Lexing.position * string

let buf_from_str str =
  let buf = Buffer.create 16 in
  Buffer.add_string buf str;
  buf

}

let space           = [ ' ' '\t' ]
let id              = ['a'-'z' 'A'-'Z' '_'] ['a'-'z' 'A'-'Z' '0'-'9' '_' '-']*

rule read tokens = parse
 | '#' '{'       { expr tokens lexbuf }
 | '\\' '"'      { uquote tokens (buf_from_str "\"") lexbuf }
 | '\\' '''      { uquote tokens (buf_from_str "'") lexbuf }
 | '\\' '\\'     { uquote tokens (buf_from_str "\\") lexbuf }
 | '\\' ' '      { uquote tokens (buf_from_str " ") lexbuf }
 | _             { uquote tokens (buf_from_str (Lexing.lexeme lexbuf)) lexbuf }
 | eof           { List.rev tokens }

and expr tokens = parse
 | '&' '&'      { expr (AND::tokens) lexbuf }
 | '|' '|'      { expr (OR::tokens) lexbuf }
 | '=' '='      { expr (EQ::tokens) lexbuf }
 | '!' '='      { expr (NEQ::tokens) lexbuf }
 | '!'          { expr (NOT::tokens) lexbuf }
 | space        { expr tokens lexbuf }
 | '('          { expr (PAREN_LEFT::tokens) lexbuf }
 | ')'          { expr (PAREN_RIGHT::tokens) lexbuf }
 | '$'          { expr (DOLLAR::tokens) lexbuf }
 | ':'          { expr (COLON::tokens) lexbuf }
 | '+'          { expr (PLUS::tokens) lexbuf }
 | '.'          { expr (DOT::tokens) lexbuf }
 | '@'          { expr (AT::tokens) lexbuf }
 | '?'          { expr (QUESTION_MARK::tokens) lexbuf }
 | '/'          { expr (SLASH::tokens) lexbuf }
 | id           {
     let v = Lexing.lexeme lexbuf in
     expr ((ID v)::tokens) lexbuf
   }
 | '''          { literal tokens (Buffer.create 16) lexbuf }
 | '}'          { read tokens lexbuf }
 | _ as c       {
     let msg = Printf.sprintf "unexpected token '%c' found" c in
     raise (Error (lexbuf.lex_curr_p, msg))
   }
 | eof         {
     let msg = Printf.sprintf "unexpected end of string" in
     raise (Error (lexbuf.lex_curr_p, msg))
   }

and uquote tokens buf = parse
 | eof         {
     let tok = STRING (Buffer.contents buf) in
     read (tok::tokens) lexbuf
   }
 | '#' '{'     {
     let tok = STRING (Buffer.contents buf) in
     expr (tok::tokens) lexbuf
   }
 | '%' '{'     {
     let tok = STRING (Buffer.contents buf) in
     expr (OPAM_OPEN::tok::tokens) lexbuf
   }
 | '\\' '"'    { Buffer.add_string buf "\""; uquote tokens buf lexbuf }
 | '\\' '''    { Buffer.add_string buf "'"; uquote tokens buf lexbuf }
 | '\\' '\\'   { Buffer.add_string buf "\\"; uquote tokens buf lexbuf }
 | '\\' ' '    { Buffer.add_string buf " "; uquote tokens buf lexbuf }
 | _           { Buffer.add_string buf (Lexing.lexeme lexbuf); uquote tokens buf lexbuf }

and literal tokens buf = parse
 | '''             {
     let tok = STRING (Buffer.contents buf) in
     expr (tok::tokens) lexbuf
   }
 | '\\' '''        {
     Buffer.add_string buf "'";
     literal tokens buf lexbuf
   }
 | [^ ''' '\\' ]+  {
     Buffer.add_string buf (Lexing.lexeme lexbuf);
     literal tokens buf lexbuf
   }
 | _ as c          {
     let msg = Printf.sprintf "unexpected token: %c" c in
     raise (Error (lexbuf.lex_curr_p, msg))
   }
 | eof         {
     let msg = Printf.sprintf "unexpected end of string" in
     raise (Error (lexbuf.lex_curr_p, msg))
   }
