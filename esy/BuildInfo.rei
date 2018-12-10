/*

  Information about performed build.

 */

type t = {
  idInfo: BuildId.Repr.t,
  timeSpent: float,
  sourceModTime: option(float),
};

let of_yojson: EsyLib.Json.decoder(t);
let to_yojson: EsyLib.Json.encoder(t);

let toFile: (EsyLib.Path.t, t) => RunAsync.t(unit);
let ofFile: EsyLib.Path.t => RunAsync.t(option(t));
