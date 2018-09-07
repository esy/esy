type t = private
  | Esy of string
  | Opam of string

include S.PRINTABLE with type t := t
include S.COMPARABLE with type t := t
include S.JSONABLE with type t := t

val parser : t Parse.t
val parse : string -> (t, string) result
val parseExn : string -> t

module Set : Set.S with type elt = t
module Map : Map.S with type key = t
