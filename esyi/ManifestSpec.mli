type t =
  | One of filename
  | ManyOpam of string list

and filename =
  | Esy of string
  | Opam of string

include S.PRINTABLE with type t := t
include S.COMPARABLE with type t := t
include S.JSONABLE with type t := t

val parser : t Parse.t
val ofString : string -> (t, string) result
val ofStringExn : string -> t

module Set : Set.S with type elt = t
module Map : Map.S with type key = t
