/** type representing os-arch tuples  */
type available = (System.Platform.t, System.Arch.t);

/** Abstract type representing platforms (os-arch tuples) a package is expected to build and work on. */
type t;

/** Default platforms expected to be supported. */
let default: t;

/** Applies opam filter, which could be from an OPAM file, on the given [t] and returns the supported platforms */
let filter: (OpamTypes.filter, t) => t;

/** [missing(~expected, ~actual)] finds platforms missing from [expected] platforms */
let missing: (~expected: t, ~actual: t) => t;

/** [isEmpty(v)] checks if [v] is empty or not */
let isEmpty: t => bool;

let empty: t;
let add: (~os: System.Platform.t, ~arch: System.Arch.t, t) => t;
let toList: t => list(available);

let union: (t, t) => t;

let ppEntry: Fmt.t(available);
let pp: Fmt.t(t);

include S.JSONABLE with type t := t;

module Map: {
  include Map.S with type key := available;
  let to_yojson: ('a => Json.t) => Json.encoder(t('a));
  let of_yojson: (Json.t => result('a, string)) => Json.decoder(t('a));
};
