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

let equal : t => t => bool;
let compare : t => t => int;

let of_yojson: EsyLib.Json.decoder(t);
let to_yojson: EsyLib.Json.encoder(t);
