type t = list(Req.t);
let empty: t;

let override: (t, t) => t;
let find: (~name: string, t) => option(Req.t);

let pp: Fmt.t(t);

include S.COMPARABLE with type t := t;
include S.JSONABLE with type t := t;

module Override: {
  type t = StringMap.Override.t(Req.t);

  include S.COMPARABLE with type t := t;
  include S.PRINTABLE with type t := t;
  include S.JSONABLE with type t := t;
};
