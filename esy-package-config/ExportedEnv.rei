type t = StringMap.t(item)
and item = {
  name: string,
  value,
  scope,
  exclusive: bool,
}
and scope =
  | Local
  | Global
and value =
  | Set(string)
  | Unset;

let empty: t;
let set: (~exclusive: bool=?, scope, string, string) => item;
let unset: (~exclusive: bool=?, scope, string) => item;

include S.COMPARABLE with type t := t;
include S.JSONABLE with type t := t;
include S.PRINTABLE with type t := t;

module Override: {
  type t = StringMap.Override.t(item);

  include S.COMPARABLE with type t := t;
  include S.PRINTABLE with type t := t;
  include S.JSONABLE with type t := t;
};
