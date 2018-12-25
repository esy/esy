type t = item StringMap.t

and item = {
  name : string;
  value : string;
}

val empty : t

include S.COMPARABLE with type t := t
include S.JSONABLE with type t := t
include S.PRINTABLE with type t := t

module Override : sig
  type t = item StringMap.Override.t

  include S.COMPARABLE with type t := t
  include S.PRINTABLE with type t := t
  include S.JSONABLE with type t := t
end
