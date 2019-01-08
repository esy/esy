type t = (kind, string)
and kind =
  | Esy
  | Opam;

include S.PRINTABLE with type t := t;
include S.COMPARABLE with type t := t;
include S.JSONABLE with type t := t;

let sexp_of_t: t => Sexplib0.Sexp.t;

let ofString: string => result(t, string);
let ofStringExn: string => t;
let parser: Parse.t(t);

let inferPackageName: t => option(string);
