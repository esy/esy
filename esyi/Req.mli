type t = private {name : string; spec : VersionSpec.t}

include S.COMPARABLE with type t := t
include S.PRINTABLE with type t := t

val to_yojson : t Json.encoder

val parse : string -> (t, string) result

val make : name:string -> spec:VersionSpec.t -> t

val matches : name:string -> version:Version.t -> t -> bool

module Map : Map.S with type key := t
module Set : Set.S with type elt := t
