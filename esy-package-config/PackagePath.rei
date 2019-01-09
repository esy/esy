/**
 * Package paths of the form
 *
 *   pkg1/pkg2
 *   @scope/pkg1/pkg2
 *
 */;

/** Pair of a path and a package name */

type t = (list(segment), string)
and segment =
  | Pkg(string)
  | AnyPkg;

let parse: string => result(t, string);

include S.PRINTABLE with type t := t;
include S.COMPARABLE with type t := t;
include S.JSONABLE with type t := t;

let to_yojson: Json.encoder(t);
let of_yojson: Json.decoder(t);
