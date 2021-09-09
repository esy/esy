[@ocaml.warning "-32"];
[@deriving (ord, show)]
type t = {
  name: string,
  resolution,
}
and resolution =
  | VersionOverride({
      version: Version.t,
      override: option(Json.t),
    })
  | SourceOverride({
      source: Source.t,
      override: Json.t,
    });
[@ocaml.warning "+32"];

let source = r =>
  switch (r.resolution) {
  | VersionOverride({version: Version.Source(source), _})
  | SourceOverride({source, _}) => Some(source)
  | VersionOverride(_) => None
  };

let resolution_to_yojson = resolution =>
  switch (resolution) {
  | VersionOverride({version, override: None}) => Version.to_yojson(version)
  | SourceOverride({source, override}) =>
    `Assoc([("source", Source.to_yojson(source)), ("override", override)])
  | VersionOverride({version, override: Some(override)}) =>
    `Assoc([
      ("version", Version.to_yojson(version)),
      ("override", override),
    ])
  };

let resolution_of_yojson = json =>
  Result.Syntax.(
    switch (json) {
    | `String(v) =>
      let* version = Version.parse(v);
      return(VersionOverride({version, override: None}));
    | `Assoc(_) =>
      let* version =
        Json.Decode.fieldOptWith(~name="version", Version.of_yojson, json);
      let* source =
        Json.Decode.fieldOptWith(
          ~name="source",
          Source.relaxed_of_yojson,
          json,
        );
      let* override =
        Json.Decode.fieldWith(~name="override", Json.of_yojson, json);
      switch (version, source) {
      | (Some(_), Some(_)) =>
        Error("expected only version or source but both were provided")
      | (Some(version), None) =>
        return(VersionOverride({version, override: Some(override)}))
      | (None, Some(source)) => return(SourceOverride({source, override}))
      | (None, None) => Error("expected version or source")
      };
    | _ => Error("expected string or object")
    }
  );

let digest = ({name, resolution}) =>
  Digestv.(
    empty
    |> add(string(name))
    |> add(json(resolution_to_yojson(resolution)))
  );

let show = ({name, resolution} as r) => {
  let resolution =
    switch (resolution) {
    | VersionOverride({version, override: _}) => Version.show(version)
    | SourceOverride({source, override: _}) =>
      Source.show(source) ++ "@" ++ Digestv.toHex(digest(r))
    };

  name ++ "@" ++ resolution;
};

let pp = (fmt, r) => Fmt.string(fmt, show(r));
