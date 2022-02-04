[@ocaml.warning "-32"];
[@deriving (show, ord)]
type t =
  | Local(Fpath.t)
  | Remote(string);

let of_yojson = (json: Json.t) =>
  switch (json) {
  | `Assoc([("type", `String("local")), ("location", `String(location))]) =>
    let location' = Fpath.of_string(location);
    switch (location') {
    | Ok(location) => Ok(Local(location))
    | Error(`Msg(_)) => Error("invalid path " ++ location)
    };
  | `Assoc([("type", `String("remote")), ("location", `String(location))]) =>
    Ok(Remote(location))
  | _ =>
    Error(
      "expected an object of the form { type: 'local' | 'remote', location: string }",
    )
  };

let to_yojson = v =>
  switch (v) {
  | Local(location) =>
    `Assoc([
      ("type", `String("local")),
      ("location", `String(Fpath.to_string(location))),
    ])
  | Remote(location) =>
    `Assoc([("type", `String("remote")), ("location", `String(location))])
  };
