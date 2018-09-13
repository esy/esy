include module type of Metadata.Source

module Override : sig
  include module type of Metadata.SourceOverride

  include S.JSONABLE with type t := t
end

include S.PRINTABLE with type t := t
include S.COMPARABLE with type t := t
include S.JSONABLE with type t := t

val parser : t Parse.t
val parse : string -> (t, string) result

module Map : Map.S with type key := t
module Set : Set.S with type elt := t
