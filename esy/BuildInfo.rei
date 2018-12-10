/*

  Information about performed build.

 */

module ModTime: {
  type t;
  let v: float => t;
  let equal: (t, t) => bool;
  let pp: Fmt.t(t);
};

type t = {
  idInfo: BuildId.Repr.t,
  timeSpent: float,
  sourceModTime: option(ModTime.t),
};

let of_yojson: EsyLib.Json.decoder(t);
let to_yojson: EsyLib.Json.encoder(t);

let toFile: (EsyLib.Path.t, t) => RunAsync.t(unit);
let ofFile: EsyLib.Path.t => RunAsync.t(option(t));
