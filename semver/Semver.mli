type t = {
  major : int;
  minor : int;
  patch : int;
  prerelease : [`Alphanumeric of string | `Numeric of int ] list;
  build : string list;
}

val compare : t -> t -> int
(** Compare two versions. *)

val parse : string -> (t, string) result
(** Parse string into semver version. *)

val pp : Format.formatter -> t -> unit
(** Pretty-printer for semver. *)

val show : t -> string
(** Convert semver to a string. *)
