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

module Pp = struct
  let pp_const v fmt () =
    Format.pp_print_string fmt v

  let pp_string =
    Format.pp_print_string

  let pp_int =
    Format.pp_print_int

  let pp_list pp_sep pp_item fmt xs =
    match xs with
    | [] -> ()
    | [x] -> pp_item fmt x
    | x::xs ->
      pp_item fmt x;
      List.iter
        (fun p -> pp_sep fmt (); pp_item fmt p)
        xs
end
