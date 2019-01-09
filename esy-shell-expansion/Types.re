[@deriving (eq, show)]
type t = list(item)
[@deriving (eq, show)]
and item =
  | String(string)
  | Var((string, option(string)));

exception UnknownShellEscape((Lexing.position, string));
exception UnmatchedChar((Lexing.position, char));
