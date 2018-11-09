open Ppx_sexp_conv_lib.Conv

type token =
  | NUMBER of float
  | IDENTIFIER of string
  | TRUE
  | FALSE
  | STRING of string
  | COLON
  | NEWLINE of int
  | INDENT
  | DEDENT
  | EOF
  [@@deriving (show, eq, sexp)]

type t =
  | Mapping of (string * t) list
  | Sequence of t list
  | Number of float
  | String of string
  | Boolean of bool
  [@@deriving (show, eq, sexp)]

exception SyntaxError of string
