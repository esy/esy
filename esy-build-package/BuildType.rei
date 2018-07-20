type t = InSource | JbuilderLike | OutOfSource | Unsafe;
let pp: Fmt.t(t);
let show: t => string;
let equal : t => t => bool;
let compare : t => t => int;
let of_yojson: EsyLib.Json.decoder(t);
let to_yojson: EsyLib.Json.encoder(t);
