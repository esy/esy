module OpamName = {
  type t = OpamPackage.Name.t;
  let to_yojson = name => `String(OpamPackage.Name.to_string(name));
  let of_yojson =
    fun
    | `String(name) => Ok(OpamPackage.Name.of_string(name))
    | _ => Error("expected string");
};

module OpamVersion = {
  type t = OpamPackage.Version.t;
  let to_yojson = name => `String(OpamPackage.Version.to_string(name));
  let of_yojson =
    fun
    | `String(name) => Ok(OpamPackage.Version.of_string(name))
    | _ => Error("expected string");
};

module NormalizedPath = {
  type t = Path.t;

  let to_yojson = p =>
    `String(Path.normalizePathSepOfFilename(Path.show(p)));

  let of_yojson = Path.of_yojson;
};

[@deriving yojson]
type opam = {
  name: OpamName.t,
  version: OpamVersion.t,
  path: NormalizedPath.t,
};

let opamfiles = opam => File.ofDir(Path.(opam.path / "files"));

type t =
  | Link({
      path: DistPath.t,
      manifest: option(ManifestSpec.t),
      kind: Source.linkKind,
    })
  | Install({
      source: (Dist.t, list(Dist.t)),
      opam: option(opam),
    });

let to_yojson = source =>
  Json.Encode.(
    switch (source) {
    | Link({path, manifest, kind}) =>
      let typ =
        switch (kind) {
        | LinkRegular => field("type", string, "link")
        | LinkDev => field("type", string, "link-dev")
        };

      assoc([
        typ,
        field("path", DistPath.to_yojson, path),
        fieldOpt("manifest", ManifestSpec.to_yojson, manifest),
      ]);
    | Install({source: (source, mirrors), opam}) =>
      assoc([
        field("type", string, "install"),
        field(
          "source",
          Json.Encode.list(Dist.to_yojson),
          [source, ...mirrors],
        ),
        fieldOpt("opam", opam_to_yojson, opam),
      ])
    }
  );

let of_yojson = json => {
  open Result.Syntax;
  open Json.Decode;
  switch%bind (fieldWith(~name="type", string, json)) {
  | "install" =>
    let* source =
      switch%bind (fieldWith(~name="source", list(Dist.of_yojson), json)) {
      | [source, ...mirrors] => return((source, mirrors))
      | _ => errorf("invalid source configuration")
      };

    let* opam = fieldOptWith(~name="opam", opam_of_yojson, json);
    Ok(Install({source, opam}));
  | "link" =>
    let* path = fieldWith(~name="path", DistPath.of_yojson, json);
    let* manifest =
      fieldOptWith(~name="manifest", ManifestSpec.of_yojson, json);
    Ok(Link({path, manifest, kind: LinkRegular}));
  | "link-dev" =>
    let* path = fieldWith(~name="path", DistPath.of_yojson, json);
    let* manifest =
      fieldOptWith(~name="manifest", ManifestSpec.of_yojson, json);
    Ok(Link({path, manifest, kind: LinkDev}));
  | typ => errorf("unknown source type: %s", typ)
  };
};
