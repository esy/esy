type t =
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

exception SyntaxError of string
