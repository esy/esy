/**

  An unique package identifier (unique within a sandbox).

 */;

type t;

include S.COMPARABLE with type t := t;
include S.PRINTABLE with type t := t;
include S.JSONABLE with type t := t;

let ppNoHash: Fmt.t(t);

let make: (string, Version.t, option(Digestv.t)) => t;
let name: t => string;
let version: t => Version.t;
let parse: string => result(t, string);

module Set: {
  include Set.S with type elt = t;

  let to_yojson: Json.encoder(t);
  let of_yojson: Json.decoder(t);
};

module Map: {
  include Map.S with type key = t;

  let to_yojson: Json.encoder('a) => Json.encoder(t('a));
  let of_yojson: Json.decoder('a) => Json.decoder(t('a));

  let pp: Fmt.t('v) => Fmt.t(t('v));
};
