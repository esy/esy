module Types = struct
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
    type version_or_pattern =
      | Version of Version.t
      | Pattern of pattern

    and pattern =
      | Any
      | Major of int
      | Minor of int * int

    type clause =
      | Patt of version_or_pattern
      | Expr of op * version_or_pattern
      | Spec of spec * version_or_pattern

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
      | Hyphen of version_or_pattern * version_or_pattern
      | Simple of clause list

    type t = range list
  end
end

module List = ListLabels

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
        xs
        ~f:(fun p -> pp_sep fmt (); pp_item fmt p)
end
