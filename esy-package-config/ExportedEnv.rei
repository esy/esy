type t = StringMap.t(item)
and item = {
  name: string,
  value: string,
  scope,
  exclusive: bool,
}
and scope =
  | Local
  | Global;

let empty: t;

include S.COMPARABLE with type t := t;
include S.JSONABLE with type t := t;
include S.PRINTABLE with type t := t;

module Override: {
  type t = StringMap.Override.t(item);

  include S.COMPARABLE with type t := t;
  include S.PRINTABLE with type t := t;
  include S.JSONABLE with type t := t;
};
