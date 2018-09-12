include module type of Metadata.Version

include S.COMMON with type t := t

val parse : ?tryAsOpam:bool -> string -> (t, string) result
val parseExn : string -> t
val toNpmVersion : t -> string

val mapPath : f:(Path.t -> Path.t) -> t -> t

module Map : Map.S with type key := t
module Set : Set.S with type elt := t
