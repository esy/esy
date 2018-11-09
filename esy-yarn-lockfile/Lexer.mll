{

  include Types

  let pp_pos fmt pos =
    Format.fprintf
      fmt
      "pos_lnum = %i pos_bol = %i pos_cnum = %i"
      pos.Lexing.pos_lnum
      pos.Lexing.pos_bol
      pos.Lexing.pos_cnum

  let ppos lexbuf =
    let start = Lexing.lexeme_start_p lexbuf in
    let stop = Lexing.lexeme_end_p lexbuf in
    Format.printf "start = (%a)@. stop = (%a)@." pp_pos start pp_pos stop

  let get_indent lexbuf =
    let pos = lexbuf.Lexing.lex_curr_p in
    pos.pos_bol

  let newline lexbuf =
    let pos = lexbuf.Lexing.lex_curr_p in
    lexbuf.lex_curr_p <-
      { pos with pos_lnum = pos.pos_lnum + 1; }

  let indent lexbuf =
    let start = Lexing.lexeme_start_p lexbuf in
    let pos = lexbuf.Lexing.lex_curr_p in
    lexbuf.lex_curr_p <-
      { pos with pos_lnum = pos.pos_lnum + 1; pos_bol = pos.pos_cnum - start.pos_cnum; }

}

let digit   = ['0'-'9']
let frac    = '.' digit*
let exp     = ['e' 'E'] ['-' '+']? digit+
let float   = digit* frac? exp?

let ws      = '\t' | ' '
let newline = '\r' | '\n' | "\r\n"
let id      = ['a'-'z' 'A'-'Z' '_' '/' '.'] ['a'-'z' 'A'-'Z' '0'-'9' '_' '-' '/' '.']*

rule read =
  parse
  | newline     { newline lexbuf; NEWLINE 0 }
  | newline ws+ { indent lexbuf; NEWLINE (get_indent lexbuf) }
  | ws       { read lexbuf }
  | "true"   { TRUE }
  | "false"  { FALSE }
  | id       { IDENTIFIER (Lexing.lexeme lexbuf) }
  | float    { NUMBER (float_of_string (Lexing.lexeme lexbuf)) }
  | '"'      { read_string (Buffer.create 16) lexbuf }
  | ':'      { COLON }
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
