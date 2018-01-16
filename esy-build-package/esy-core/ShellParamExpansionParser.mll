{

  include ShellParamExpansionSupport

  let finalize_string result = function
    | `Init -> result
    | `String buf -> String (Buffer.contents buf)::result

}

let safechars   = [^ '\\' ]
let id          = ['a'-'z' 'A'-'Z' '_'] ['a'-'z' 'A'-'Z' '0'-'9' '_']*

rule read result state = parse
 | '$' (id as id) {
      let item = Var (id, None) in
      let result = finalize_string result state in
      read (item::result) `Init lexbuf
    }
 | '$' '{' (id as id) '}' {
      let item = Var (id, None) in
      let result = finalize_string result state in
      read (item::result) `Init lexbuf
    }
 | '$' '{' (id as id) ':' '-' ([^ '}' ]+ as default) '}' {
      let item = Var (id, Some default) in
      let result = finalize_string result state in
      read (item::result) `Init lexbuf
    }
 | safechars     { read_string result state (Lexing.lexeme lexbuf) lexbuf }
 | '\\' '"'      { read_string result state (Lexing.lexeme lexbuf) lexbuf }
 | '\\' '''      { read_string result state (Lexing.lexeme lexbuf) lexbuf }
 | '\\' '\\'     { read_string result state (Lexing.lexeme lexbuf) lexbuf }
 | '\\' ' '      { read_string result state (Lexing.lexeme lexbuf) lexbuf }

 | '\\' _ as c   { raise (UnknownShellEscape (lexbuf.lex_curr_p, c)) }
 | _ as c        { raise (UnmatchedChar (lexbuf.lex_curr_p, c)) }

 | eof           {
    let result = finalize_string result state in
    List.rev result
  }

 and read_string result state string = parse
  | "" {
    let (state, buf) = match state with
    | `Init -> let buf = Buffer.create 16 in `String buf, buf
    | `String buf -> state, buf
    in
    Buffer.add_string buf string;
    read result state lexbuf
  }

 {

  let parse_exn v =
    let lexbuf = Lexing.from_string v in
    read [] `Init lexbuf

  let parse v =
    try Ok (parse_exn v)
    with
    | UnmatchedChar (pos, c) ->
      let msg = Printf.sprintf "unknown char: '%c' at position %d" c pos.Lexing.pos_cnum
      in Error msg

 }
