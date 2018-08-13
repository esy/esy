type token =
  | NUMBER of float
  | IDENTIFIER of string
  | TRUE
  | FALSE
  | STRING of string
  | COLON
  | COMMA
  | NEWLINE
  | EOF
  [@@deriving (show, eq)]

type tokens =
  token list
  [@@deriving (show, eq)]

type t =
  | Mapping of (string * t) list
  | Number of float
  | String of string
  | Boolean of bool
  [@@deriving (show, eq)]

exception SyntaxError of string
