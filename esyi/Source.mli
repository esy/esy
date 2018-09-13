include module type of Metadata.Source

module Override : sig
  include module type of Metadata.SourceOverride

  include S.JSONABLE with type t := t

  val empty : t
end

include S.PRINTABLE with type t := t
include S.COMPARABLE with type t := t
include S.JSONABLE with type t := t

val manifest : source -> SandboxSpec.ManifestSpec.t option
val source_of_yojson : source Json.decoder
val source_to_yojson : source Json.encoder

val parser : t Parse.t
val parse : string -> (t, string) result

module Map : Map.S with type key := t
module Set : Set.S with type elt := t
