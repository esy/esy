/** An expression */;

module Expr = {
  [@deriving (show, eq, ord)]
  type t =
    | Concat(list(t))
    | Var(name)
    | EnvVar(string)
    | String(string)
    | Bool(bool)
    | Condition(t, t, t)
    | And(t, t)
    | Or(t, t)
    | Not(t)
    | Rel(relop, t, t)
    | Colon
    | PathSep
  and opamVar = (list(string), string)
  and name = (option(string), string)
  and relop =
    | EQ
    | NEQ;
};

module Value = {
  [@deriving (show, eq, ord)]
  type t =
    | String(string)
    | Bool(bool);
};

type scope = Expr.name => option(Value.t);
