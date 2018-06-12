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
    | Colon
    | PathSep
    | OpamVar of opamVar
    [@@deriving (show, eq)]

  and opamVar = string list * string

  and name = string option * string
    [@@deriving (show, eq)]
end


module Value = struct
  type t =
    | String of string
    | Bool of bool
    [@@deriving (show, eq)]
end

type scope = Expr.name -> Value.t option
