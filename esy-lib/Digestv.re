[@deriving ord]
type part = Digest.t;

let part_to_yojson = v => Json.Encode.string(Digest.to_hex(v));
let part_of_yojson = json => {
  open Result.Syntax;
  let* part = Json.Decode.string(json);
  return(Digest.from_hex(part));
};

[@deriving ord]
type t = list(part);

let empty = [];

let string = v => Digest.string(v);
let json = v => string(Yojson.Safe.to_string(v));

let add = (part, digest) => [part, ...digest];

let ofString = v => [string(v)];
let ofJson = v => [json(v)];

let ofFile = path => {
  open RunAsync.Syntax;
  let* data = Fs.readFile(path);
  return(ofString(data));
};

let combine = (a, b) => a @ b;
let (+) = combine;

let toHex = digest =>
  digest
  |> List.map(~f=Digest.to_hex)
  |> String.concat("$$")
  |> Digest.string
  |> Digest.to_hex;
