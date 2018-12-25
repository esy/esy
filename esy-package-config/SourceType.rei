/**

  Source type.

 */

type t =
  | /** Sources don't change so we can build it once. */
    Immutable
  | /** Same as immutable but depends on transient builds. */
    ImmutableWithTransientDependencies
  | /** Sources can change. */
    Transient;

let pp: Fmt.t(t);
let show: t => string;

include S.COMPARABLE with type t := t;
include S.JSONABLE with type t := t;
