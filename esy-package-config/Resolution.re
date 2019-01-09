[@ocaml.warning "-32"];
[@deriving (ord, show)]
type t = {
  name: string,
  resolution,
}
and resolution =
  | Version(Version.t)
  | SourceOverride{
      source: Source.t,
      override: Json.t,
    };
[@ocaml.warning "+32"];

let source = r =>
  switch (r.resolution) {
  | Version(Version.Source(source)) => Some(source)
  | Version(_) => None
  | SourceOverride({source, _}) => Some(source)
  };

let resolution_to_yojson = resolution =>
  switch (resolution) {
  | Version(v) => `String(Version.show(v))
  | SourceOverride({source, override}) =>
    `Assoc([("source", Source.to_yojson(source)), ("override", override)])
  };

let resolution_of_yojson = json =>
  Result.Syntax.(
    switch (json) {
    | `String(v) =>
      let%bind version = Version.parse(v);
      return(Version(version));
    | `Assoc(_) =>
      let%bind source =
        Json.Decode.fieldWith(~name="source", Source.relaxed_of_yojson, json);
      let%bind override =
        Json.Decode.fieldWith(~name="override", Json.of_yojson, json);
      return(SourceOverride({source, override}));
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
    | Version(version) => Version.show(version)
    | SourceOverride({source, override: _}) =>
      Source.show(source) ++ "@" ++ Digestv.toHex(digest(r))
    };

  name ++ "@" ++ resolution;
};

let pp = (fmt, r) => Fmt.string(fmt, show(r));
