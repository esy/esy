type t =
    Npm of SemverVersion.Version.t
  | Opam of OpamPackageVersion.Version.t
  | Source of Source.t

include S.COMMON with type t := t

val parse : ?tryAsOpam:bool -> string -> (t, string) result
val parseExn : string -> t

val showSimple : t -> string

module Map : Map.S with type key := t
module Set : Set.S with type elt := t
