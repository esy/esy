{

  exception Error of string

  let unexpected lexbuf =
    raise (Error ("Unexpected char: " ^ Lexing.lexeme lexbuf))

}

let n = ['0' - '9']
let a = ['a' - 'z'] | ['A'-'Z'] | ['-']
let an = a | n

let n_pre_id = n+
let an_pre_id = (n* a an*)
let build_id = an+

rule version = parse
  | (n+ as major) '.' (n+ as minor) '.' (n+ as patch) eof
    {
      let version = (
          int_of_string major,
          int_of_string minor,
          int_of_string patch
      ) in
      version, [], []
    }
  | (n+ as major) '.' (n+ as minor) '.' (n+ as patch) '-' (n_pre_id as id)
    {
      let version = (
          int_of_string major,
          int_of_string minor,
          int_of_string patch
      ) in
      pre version [`Numeric (int_of_string id)] lexbuf
    }
  | (n+ as major) '.' (n+ as minor) '.' (n+ as patch) '-' (an_pre_id as id)
    {
      let version = (
          int_of_string major,
          int_of_string minor,
          int_of_string patch
      ) in
      pre version [`Alphanumeric id] lexbuf
    }
  | (n+ as major) '.' (n+ as minor) '.' (n+ as patch) '+' (build_id as id)
    {
      let version = (
          int_of_string major,
          int_of_string minor,
          int_of_string patch
      ) in
      build version [] [id] lexbuf
    }
  | _ { unexpected lexbuf }

and pre version acc = parse
  | '.' (n_pre_id as id) {
      pre version ((`Numeric (int_of_string id))::acc) lexbuf
    }
  | '.' (an_pre_id as id) {
      pre version ((`Alphanumeric id)::acc) lexbuf
    }
  | '+' {
      if List.length acc = 0
      then raise (Error "empty prerelease")
      else build version (List.rev acc) [] lexbuf
    }
  | eof {
      version, (List.rev acc), []
    }
  | _ { unexpected lexbuf }

and build version pre acc = parse
  | '.' (build_id as id) {
      if List.length acc = 0
      then raise (Error "invalid build")
      else build version pre (id::acc) lexbuf
    }
  | eof {
      if List.length acc = 0
      then raise (Error "empty build")
      else version, pre, (List.rev acc)
    }
  | _ { unexpected lexbuf }
