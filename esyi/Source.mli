include module type of Metadata.Source

include S.COMMON with type t := t

val parser : t Parse.t
val parse : string -> (t, string) result

module Map : Map.S with type key := t
module Set : Set.S with type elt := t
