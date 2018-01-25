exception UnmatchedChar of (Lexing.position * char)
exception UnmatchedVarBrace of (Lexing.position * unit)

type t =
  token list
  [@@deriving (show, eq)]

and token =
  | String of string
  | Expr of expr list
  [@@deriving (show, eq)]

and expr =
  | Var of name
  | EnvVar of string
  | Literal of string
  | Colon
  | PathSep
  [@@deriving (show, eq)]

and name = string list

let buf_from_str str =
  let buf = Buffer.create 16 in
  Buffer.add_string buf str;
  buf

let nested rule lexbuf =
  let value  = Lexing.lexeme lexbuf in
  let lexbuf = Lexing.from_string value in
  let rec read tokens =
    match rule lexbuf with
    | `Token tok -> read (tok::tokens)
    | `EOF -> List.rev tokens
  in read []
