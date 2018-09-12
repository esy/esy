(**

  Request for a package, a pair of package name and a version spec (constraint
  or source spec).


 *)

include module type of Types.Req

include S.COMPARABLE with type t := t
include S.PRINTABLE with type t := t

val to_yojson : t Json.encoder

val parse : string -> (t, string) result

val make : name:string -> spec:VersionSpec.t -> t

val matches : name:string -> version:Version.t -> t -> bool

module Map : Map.S with type key := t
module Set : Set.S with type elt := t
