/*

  Information about performed build.

 */

type t = {
  timeSpent: float,
  sourceModTime: option(float),
};

let of_yojson : EsyLib.Json.decoder(t);
let to_yojson : EsyLib.Json.encoder(t);

let toFile : (EsyLib.Path.t, t) => Run.t(unit, _);
let ofFile : (EsyLib.Path.t) => Run.t(option(t), _);
