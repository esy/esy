type t = BuildEnv.t;

let empty: t;

include S.JSONABLE with type t := t;
