type t = BuildEnv.t

val empty : t

include S.JSONABLE with type t := t
