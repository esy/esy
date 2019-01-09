type t = list(Command.t);
include S.COMPARABLE with type t := t;
include S.JSONABLE with type t := t;
include S.PRINTABLE with type t := t;

let empty: t;
