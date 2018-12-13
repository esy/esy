(**

  An unique package identifier (unique within a sandbox).

 *)

type t

include S.COMPARABLE with type t := t
include S.PRINTABLE with type t := t
include S.JSONABLE with type t := t

val ppNoHash : t Fmt.t

val make : string -> Version.t -> Digestv.t option -> t
val name : t -> string
val version : t -> Version.t
val parse : string -> (t, string) result

module Set : sig
  include Set.S with type elt = t

  val to_yojson : t Json.encoder
  val of_yojson : t Json.decoder
end

module Map : sig
  include Map.S with type key = t

  val to_yojson : 'a Json.encoder -> 'a t Json.encoder
  val of_yojson : 'a Json.decoder -> 'a t Json.decoder
end
