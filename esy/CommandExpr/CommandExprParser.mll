{ include CommandExprParserSupport }

let space       = [ ' ' '\t' ]
let colon       = ':'
let path_sep    = '/'
let paren_close = '}'
let var_open    = '#' '{'
let id          = ['a'-'z' 'A'-'Z' '_'] ['a'-'z' 'A'-'Z' '0'-'9' '_']*

let pkg_name        = ['a'-'z' 'A'-'Z' '_'] ['a'-'z' 'A'-'Z' '0'-'9' '_' '-']*
let scoped_pkg_name = '@' pkg_name '/' pkg_name

let capture_name = ['a'-'z' 'A'-'Z' '_'] ['a'-'z' 'A'-'Z' '0'-'9' '-' '_' '.' '/']*

rule read result = parse
 | var_open      { expr result [] lexbuf }
 | '\\' '"'      { uquote result (buf_from_str "\"") lexbuf }
 | '\\' '''      { uquote result (buf_from_str "'") lexbuf }
 | '\\' '\\'     { uquote result (buf_from_str "\\") lexbuf }
 | '\\' ' '      { uquote result (buf_from_str " ") lexbuf }
 | _             { uquote result (buf_from_str (Lexing.lexeme lexbuf)) lexbuf }
 | eof { List.rev result }

and expr result tokens = parse
 | space        { expr result tokens lexbuf }
 | colon        { expr result (Colon::tokens) lexbuf }
 | path_sep     { expr result (PathSep::tokens) lexbuf }
 | '@' capture_name {
     let name = nested name lexbuf in
     expr result ((Var name)::tokens) lexbuf
   }
 | capture_name     {
     let name = nested name lexbuf in
     expr result ((Var name)::tokens) lexbuf
   }
 | '$' id       {
     let v = Lexing.lexeme lexbuf in
     let v = StringLabels.sub ~pos:1 ~len:(String.length v - 1) v in
     let tok = EnvVar v in
     expr result (tok::tokens) lexbuf
   }
 | '''          { literal result tokens (Buffer.create 16) lexbuf }
 | paren_close  { let expr = Expr (List.rev tokens) in read (expr::result) lexbuf }

and name = parse
  | scoped_pkg_name as v  { `Token v }
  | pkg_name as v         { `Token v }
  | id as v               { `Token v }
  | '.'                   { name lexbuf }
  | _ as c                { raise (UnmatchedChar (lexbuf.lex_curr_p, c)) }
  | eof                   { `EOF }

and uquote result buf = parse
 | eof         { let tok = String (Buffer.contents buf) in read (tok::result) lexbuf }
 | var_open    {
     let tok = String (Buffer.contents buf) in
     expr (tok::result) [] lexbuf
   }
 | '\\' '"'    { Buffer.add_string buf "\""; uquote result buf lexbuf }
 | '\\' '''    { Buffer.add_string buf "'"; uquote result buf lexbuf }
 | '\\' '\\'   { Buffer.add_string buf "\\"; uquote result buf lexbuf }
 | '\\' ' '    { Buffer.add_string buf " "; uquote result buf lexbuf }
 | _           { Buffer.add_string buf (Lexing.lexeme lexbuf); uquote result buf lexbuf }

and literal result tokens buf = parse
 | ''' {
     let tok = Literal (Buffer.contents buf) in
     expr result (tok::tokens) lexbuf
   }
 | '\\' '''        {
     Buffer.add_string buf "'";
     literal result tokens buf lexbuf
   }
 | [^ ''' '\\' ]+       {
     Buffer.add_string buf (Lexing.lexeme lexbuf);
     literal result tokens buf lexbuf
   }
 | _ as c          { raise (UnmatchedChar (lexbuf.lex_curr_p, c)) }
