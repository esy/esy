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
