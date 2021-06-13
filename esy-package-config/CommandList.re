[@ocaml.warning "-32"];
[@deriving (show, ord)]
type t = list(Command.t);

let empty = [];

let of_yojson = (json: Json.t) =>
  Result.Syntax.(
    switch (json) {
    | `Null => return([])
    | `List(commands) =>
      Json.Decode.list(Command.of_yojson, `List(commands))
    | `String(command) =>
      let* command = Command.of_yojson(`String(command));
      return([command]);
    | _ => Error("expected either a null, a string or an array")
    }
  );

let to_yojson = commands => `List(List.map(~f=Command.to_yojson, commands));
