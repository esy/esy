exception UnknownShellEscape of (Lexing.position * string)
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
  | Var of string
  | EnvVar of string
  | Literal of string
  | Colon
  | PathSep
  [@@deriving (show, eq)]

let buf_from_str str =
  let buf = Buffer.create 16 in
  Buffer.add_string buf str;
  buf
