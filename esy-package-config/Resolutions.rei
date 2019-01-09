type t;

let empty: t;
let add: (string, Resolution.resolution, t) => t;
let find: (t, string) => option(Resolution.t);

let entries: t => list(Resolution.t);

let to_yojson: Json.encoder(t);
let of_yojson: Json.decoder(t);

let digest: t => Digestv.t;
