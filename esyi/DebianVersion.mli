(**
 * Debian definition of version ordering.
 *
 * See https://opam.ocaml.org/doc/Manual.html#version-ordering for details.
 *)

type t

val parse : string -> (t, string) result
val parseExn : string -> t

val toString : t -> string
val show : t -> string
val equal : t -> t -> bool
val compare : t -> t -> int

(**
 * Yojson protocol
 *)
val to_yojson : t -> Json.t
val of_yojson : Json.t -> (t, string) result

(**
 * Semver API.
 *
 * Note that this isn't always possible to treat Debian-style versions (which
 * are essentially arbitrary alphanumeric versions) as semver, * this is why
 * returns an option.
 *)
module AsSemver : sig

  val major : t -> int option
  val minor : t -> int option
  val patch : t -> int option

  (**
  * Try to guess the next patch version (in a semver sense).
  *)
  val nextPatch : t -> t option

  (**
  * Try to guess the next minor version (in a semver sense).
  *
  * Note that this isn't always possible with arbitrary alphanumeric versions,
  * this is why returns an option.
  *)
  val nextMinor : t -> t option
end
