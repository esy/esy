type t = Command.t list
include S.COMPARABLE with type t := t
include S.JSONABLE with type t := t
include S.PRINTABLE with type t := t

val empty : t
