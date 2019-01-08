type t =
  | Parsed(list(string))
  | Unparsed(string);

include S.COMPARABLE with type t := t;
include S.JSONABLE with type t := t;
include S.PRINTABLE with type t := t;
