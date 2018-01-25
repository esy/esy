(**
 * Split shell string into a list of arguments suitable for execv-family of
 * functions.
 *
 * Based on https://stackoverflow.com/questions/29401883/parse-shell-quoted-string-into-execv-compatible-argument-vector?rq=1<Paste>
 *)

{

  exception UnknownShellEscape of string
  exception UnmatchedChar of char

  let buf_from_str str =
    let buf = Buffer.create 16 in
    Buffer.add_string buf str;
    buf

}

let safechars = [^ '"' ''' '\\' ' ' '\t']+
let space = [ ' ' '\t' ]+

rule shell_command argv = parse
 | space         { shell_command argv lexbuf }
 | safechars     { uquote argv (buf_from_str (Lexing.lexeme lexbuf)) lexbuf }
 | '\\' '"'      { uquote argv (buf_from_str "\"") lexbuf }
 | '\\' '''      { uquote argv (buf_from_str "'") lexbuf }
 | '\\' '\\'     { uquote argv (buf_from_str "\\") lexbuf }
 | '\\' ' '      { uquote argv (buf_from_str " ") lexbuf }
 | '\\' _ as c   { raise (UnknownShellEscape c) }
 | '"'           { dquote argv (Buffer.create 16) lexbuf }
 | '''           { squote argv (Buffer.create 16) lexbuf }
 | _ as c        { raise (UnmatchedChar c) }
 | eof { List.rev argv }
and uquote argv buf = parse
 | (space|eof) { shell_command ((Buffer.contents buf)::argv) lexbuf }
 | '\\' '"'    { Buffer.add_string buf "\""; uquote argv buf lexbuf }
 | '\\' '''    { Buffer.add_string buf "'"; uquote argv buf lexbuf }
 | '\\' '\\'   { Buffer.add_string buf "\\"; uquote argv buf lexbuf }
 | '\\' ' '    { Buffer.add_string buf " "; uquote argv buf lexbuf }
 | '\\' _ as c { raise (UnknownShellEscape c) }
 | '"'         { dquote argv buf lexbuf }
 | '''         { squote argv buf lexbuf }
 | safechars   { Buffer.add_string buf (Lexing.lexeme lexbuf); uquote argv buf lexbuf }
 | _ as c      { raise (UnmatchedChar c) }
and dquote argv buf = parse
 | '"' (space|eof) { shell_command ((Buffer.contents buf)::argv) lexbuf }
 | '"' '"'         { dquote argv buf lexbuf }
 | '"' '''         { squote argv buf lexbuf }
 | '"'             { uquote argv buf lexbuf }
 | '\\' '"'        { Buffer.add_string buf "\""; dquote argv buf lexbuf }
 | '\\' '\\'       { Buffer.add_string buf "\\"; dquote argv buf lexbuf }
 | '\\' _ as c     { raise (UnknownShellEscape c) }
 | [^ '"' '\\' ]+  { Buffer.add_string buf (Lexing.lexeme lexbuf); dquote argv buf lexbuf }
 | _ as c          { raise (UnmatchedChar c) }
and squote argv buf = parse
 | ''' (space|eof) { shell_command ((Buffer.contents buf)::argv) lexbuf }
 | ''' '''         { squote argv buf lexbuf }
 | ''' '"'         { dquote argv buf lexbuf }
 | '''             { uquote argv buf lexbuf }
 | [^ ''' ]+       { Buffer.add_string buf (Lexing.lexeme lexbuf); squote argv buf lexbuf }
 | _ as c          { raise (UnmatchedChar c) }

{

  let split v =
    let open Run.Syntax in
    let lexbuf = Lexing.from_string v in
    try Ok (shell_command [] lexbuf) with
    | UnknownShellEscape s ->
      error (Printf.sprintf "unknown shell escape sequence: %s" s)

}
