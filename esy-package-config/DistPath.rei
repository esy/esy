/**

  This represents symbolic paths used in dists/sources/source-specs.

  They are always rendered using forward slashes (/), unix-like.

  [DistPath.t] values are relative to some base [Path.t] value.

 */;

type t;

include S.JSONABLE with type t := t;
include S.COMPARABLE with type t := t;

let v: string => t;
let (/): (t, string) => t;

/** [toPath base p] converts [p] to [Path.t] by rebasing on top of [base]. */

let toPath: (Path.t, t) => Path.t;

let ofPath: Path.t => t;

let make: (~base: Path.t, Path.t) => t;
let rebase: (~base: t, t) => t;

let sexp_of_t: t => Sexplib0.Sexp.t;

let pp: Fmt.t(t);
let show: t => string;
let showPretty: t => string;
