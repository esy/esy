/** Abstract type representing platforms (os-arch tuples) a package is expected to build and work on. */
type t;

/** Default platforms expected to be supported. */
let default: t;

/** Applies opam filter, which could be from an OPAM file, on the given [t] and returns the supported platforms */
let filter: (OpamTypes.filter, t) => t;

/** [missing(~expected, ~actual)] finds platforms missing from [expected] platforms */
let missing: (~expected:t, ~actual:t) => t;

/** [isEmpty(v)] checks if [v] is empty or not */
let isEmpty: t => bool;

include S.JSONABLE with type t := t;
