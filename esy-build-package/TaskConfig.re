module Path = EsyLib.Path;
module Result = EsyLib.Result;
module Let_syntax = Result.Syntax.Let_syntax;

module Env = {
  type t = Bos.OS.Env.t;
  let pp = (_fmt, _env) => ();
  let of_yojson = (json: Yojson.Safe.json) =>
    switch (json) {
    | `Assoc(items) =>
      let add_to_map = (res, (key, value)) =>
        switch (res, value) {
        | (Ok(res), `String(value)) =>
          Ok(Astring.String.Map.add(key, value, res))
        | _ => Error("expected a string value")
        };
      List.fold_left(add_to_map, Ok(Astring.String.Map.empty), items);
    | _ => Error("expected an object")
    };
  let to_yojson = (env: t) => {
    let f = (k, v, items) => [(k, `String(v)), ...items];
    let items = Astring.String.Map.fold(f, env, []);
    `Assoc(items);
  };
};

[@deriving yojson]
type t = {
  id: string,
  name: string,
  version: string,
  sourceType: SourceType.t,
  buildType: BuildType.t,
  build: list(list(string)),
  install: list(list(string)),
  sourcePath: string,
  env: Env.t,
};
