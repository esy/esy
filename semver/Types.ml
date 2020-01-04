module Version = struct
  type t = {
    major : int;
    minor : int;
    patch : int;
    prerelease : prerelease_id list;
    build : string list;
  }

  and prerelease_id =
    | N of int
    | A of string
end

module Formula = struct
  type patt =
    | Any
    | Major of int
    | Minor of int * int
    | Version of Version.t

  type clause =
    | Patt of patt
    | Expr of op * patt
    | Spec of spec * patt

  and op =
  | GT
  | GTE
  | LT
  | LTE
  | EQ

  and spec =
    | Tilda
    | Caret

  type range =
    | Hyphen of patt * patt
    | Conj of clause list

  type t = range list
end
