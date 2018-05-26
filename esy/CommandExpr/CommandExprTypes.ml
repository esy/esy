(** An expression *)

module Expr = struct
  type t =
    | Concat of t list
    | Var of name
    | EnvVar of string
    | String of string
    | Condition of t * t * t
    | And of t * t
    | Colon
    | PathSep
    [@@deriving (show, eq)]

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
