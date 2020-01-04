module Version : sig
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

  val compare : t -> t -> int
  (** Compare two versions. *)

  val parse : string -> (t, string) result
  (** Parse string into semver version. *)

  val pp : Format.formatter -> t -> unit
  (** Pretty-printer for semver. *)

  val show : t -> string
  (** Convert semver to a string. *)
end

module Formula : sig
  type t = range list

  and range =
    | Hyphen of patt * patt
    | Conj of clause list

  and patt =
    | Any
    | Major of int
    | Minor of int * int
    | Version of Version.t

  and clause =
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
end
