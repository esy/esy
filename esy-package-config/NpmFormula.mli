type t = Req.t list
val empty : t

val override : t -> t -> t
val find : name:string -> t -> Req.t option

val pp : t Fmt.t

include S.COMPARABLE with type t := t
include S.JSONABLE with type t := t

module Override : sig
  type t = Req.t StringMap.Override.t

  include S.COMPARABLE with type t := t
  include S.PRINTABLE with type t := t
  include S.JSONABLE with type t := t
end
