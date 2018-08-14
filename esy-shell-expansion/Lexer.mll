{

  include Types

  let finalizeString result = function
    | `Init -> result
    | `String buf -> String (Buffer.contents buf)::result

}

let id          = ['a'-'z' 'A'-'Z' '_'] ['a'-'z' 'A'-'Z' '0'-'9' '_']*

rule read result state = parse
 | '$' (id as id) {
      let item = Var (id, None) in
      let result = finalizeString result state in
      read (item::result) `Init lexbuf
    }
 | '$' '{' (id as id) '}' {
      let item = Var (id, None) in
      let result = finalizeString result state in
      read (item::result) `Init lexbuf
    }
 | '$' '{' (id as id) ':' '-' ([^ '}' ]+ as default) '}' {
      let item = Var (id, Some default) in
      let result = finalizeString result state in
      read (item::result) `Init lexbuf
    }
 | '\\' '"'      { read_string result state (Lexing.lexeme lexbuf) lexbuf }
 | '\\' '''      { read_string result state (Lexing.lexeme lexbuf) lexbuf }
 | '\\' '\\'     { read_string result state (Lexing.lexeme lexbuf) lexbuf }
 | '\\' '/'      { read_string result state (Lexing.lexeme lexbuf) lexbuf }
 | '\\' ' '      { read_string result state (Lexing.lexeme lexbuf) lexbuf }
 | _             { read_string result state (Lexing.lexeme lexbuf) lexbuf }

 | eof           {
    let result = finalizeString result state in
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

 }
