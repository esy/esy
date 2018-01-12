exception UnknownShellEscape of string
exception UnmatchedChar of char
exception UnmatchedVarBrace

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
