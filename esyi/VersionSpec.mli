(**
 * This representes a concrete version which at some point will be resolved to a
 * concrete version Version.t.
 *)

type t =
  | Npm of SemverVersion.Formula.DNF.t
  | NpmDistTag of string * SemverVersion.Version.t option
  | Opam of OpamPackageVersion.Formula.DNF.t
  | Source of SourceSpec.t

val pp : t Fmt.t
val toString : t -> string
val to_yojson : t -> [> `String of string ]

include S.COMPARABLE with type t := t

val parseAsNpm : string -> (t, string) result
val parseAsOpam : string -> (t, string) result

val matches : version:Version.t -> t -> bool
val ofVersion : Version.t -> t
