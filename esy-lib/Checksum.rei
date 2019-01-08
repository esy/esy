type t = (kind, string)
and kind =
  | Md5
  | Sha1
  | Sha256
  | Sha512;

include S.JSONABLE with type t := t;
include S.PRINTABLE with type t := t;
include S.COMPARABLE with type t := t;

let sexp_of_t: t => Sexplib0.Sexp.t;
let parser: Parse.t(t);
let parse: string => result(t, string);

let computeOfFile: (~kind: kind=?, Path.t) => RunAsync.t(t);
let checkFile: (~path: Path.t, t) => RunAsync.t(unit);
