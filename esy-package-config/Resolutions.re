type t = StringMap.t(Resolution.t);

let empty = StringMap.empty;

let find = (resolutions, name) => StringMap.find_opt(name, resolutions);

let add = (name, resolution, resolutions) =>
  StringMap.add(name, {Resolution.name, resolution}, resolutions);

let entries = StringMap.values;

let digest = resolutions => {
  let f = (_, resolution, digest) =>
    Digestv.(digest + Resolution.digest(resolution));
  StringMap.fold(f, resolutions, Digestv.empty);
};

let to_yojson = v => {
  let items = {
    let f = (name, {Resolution.resolution, _}, items) => [
      (name, Resolution.resolution_to_yojson(resolution)),
      ...items,
    ];

    StringMap.fold(f, v, []);
  };

  `Assoc(items);
};

let of_yojson = {
  open Result.Syntax;
  let parseKey = k =>
    switch (PackagePath.parse(k)) {
    | [@implicit_arity] Ok(_path, name) => Ok(name)
    | Error(err) => Error(err)
    };

  let parseValue = (name, json) =>
    switch (json) {
    | `String(v) =>
      let* version =
        switch (Astring.String.cut(~sep="/", name)) {
        | Some(("@opam", _)) => Version.parse(~tryAsOpam=true, v)
        | _ => Version.parse(v)
        };

      return({
        Resolution.name,
        resolution: VersionOverride({version, override: None}),
      });
    | `Assoc(_) =>
      let* resolution = Resolution.resolution_of_yojson(json);
      return({Resolution.name, resolution});
    | _ => Error("expected string")
    };

  fun
  | `Assoc(items) => {
      let f = (res, (key, json)) => {
        let* key = parseKey(key);
        let* value = parseValue(key, json);
        Ok(StringMap.add(key, value, res));
      };

      Result.List.foldLeft(~f, ~init=empty, items);
    }
  | _ => Error("expected object");
};
