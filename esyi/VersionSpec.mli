(**
 * This representes a concrete version which at some point will be resolved to a
 * concrete version Version.t.
 *)

type t =
  | Npm of SemverVersion.Formula.DNF.t
  | NpmDistTag of string
  | Opam of OpamPackageVersion.Formula.DNF.t
  | Source of SourceSpec.t


include S.COMPARABLE with type t := t
include S.PRINTABLE with type t := t

val to_yojson : t Json.encoder

val parserNpm : t Parse.t
val parserOpam : t Parse.t

val ofVersion : Version.t -> t
