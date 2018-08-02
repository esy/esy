(** An expression *)

module Expr = struct
  type t =
    | Concat of t list
    | Var of name
    | EnvVar of string
    | String of string
    | Bool of bool
    | Condition of t * t * t
    | And of t * t
    | Or of t * t
    | Not of t
    | Rel of relop * t * t
    | Colon
    | PathSep
    [@@deriving (show, eq, ord)]

  and opamVar = string list * string

  and name = string option * string

  and relop =
    | EQ
    | NEQ
end


module Value = struct
  type t =
    | String of string
    | Bool of bool
    [@@deriving (show, eq, ord)]
end

type scope = Expr.name -> Value.t option
