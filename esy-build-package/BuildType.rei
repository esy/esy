/**

  Build type.

 */
type t =
  /** Build writes to its source root (we preventively copy source root) */
  | InSource
  /** Build writes to _build dir inside of its source root (jbuilder/dune/ocamlbuild) */
  | JbuilderLike
  /** Build only writes to a directory specified via $cur__target_dir */
  | OutOfSource
  /** Build write to its source root (but we don't prevent that) */
  | Unsafe;

let pp: Fmt.t(t);
let show: t => string;

let equal : t => t => bool;
let compare : t => t => int;

let of_yojson: EsyLib.Json.decoder(t);
let to_yojson: EsyLib.Json.encoder(t);
