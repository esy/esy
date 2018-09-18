/**

  Source type.

 */
type t =
  /** Immutable means sources don't change so we can build it once. */
  | Immutable
  /** Transient means sources can change so we should check for that and re-build */
  | Transient;

let pp: Fmt.t(t);
let show: t => string;

include S.COMPARABLE with type t := t
include S.JSONABLE with type t := t
