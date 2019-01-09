type part;

let part_to_yojson: Json.encoder(part);
let part_of_yojson: Json.decoder(part);

type t;

include S.COMPARABLE with type t := t;

let ofFile: Path.t => RunAsync.t(t);
let ofString: string => t;
let ofJson: Json.t => t;

let empty: t;

let string: string => part;
let json: Json.t => part;

let add: (part, t) => t;

let combine: (t, t) => t;
let (+): (t, t) => t;

let toHex: t => string;
