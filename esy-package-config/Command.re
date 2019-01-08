[@ocaml.warning "-32"];
[@deriving (show, ord)]
type t =
  | Parsed(list(string))
  | Unparsed(string);

let of_yojson = (json: Json.t) =>
  switch (json) {
  | `String(command) => Ok(Unparsed(command))
  | `List(command) =>
    switch (Json.Decode.(list(string, `List(command)))) {
    | Ok(args) => Ok(Parsed(args))
    | Error(err) => Error(err)
    }
  | _ => Error("expected either a string or an array of strings")
  };

let to_yojson = v =>
  switch (v) {
  | Parsed(args) => `List(List.map(~f=arg => `String(arg), args))
  | Unparsed(line) => `String(line)
  };
