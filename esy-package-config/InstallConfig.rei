type t = {pnp: bool};

let empty: t;

let to_yojson: Json.encoder(t);
let of_yojson: Json.decoder(t);
