type value =
  | Set(string)
  | Unset;
type t = StringMap.t(item)
and item = {
  name: string,
  value,
};

let empty: t;
let set: (string, string) => item;
let unset: string => item;

include S.COMPARABLE with type t := t;
include S.JSONABLE with type t := t;
include S.PRINTABLE with type t := t;

module Override: {
  type t = StringMap.Override.t(item);

  include S.COMPARABLE with type t := t;
  include S.PRINTABLE with type t := t;
  include S.JSONABLE with type t := t;
};
