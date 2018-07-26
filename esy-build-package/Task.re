module Path = EsyLib.Path;
module Result = EsyLib.Result;
module Let_syntax = Result.Syntax.Let_syntax;

open Result.Syntax;

module Env = {
  type t = Astring.String.Map.t(Config.Value.t);
  let pp = (_fmt, _env) => ();
  let of_yojson = (json: Yojson.Safe.json) =>
    switch (json) {
    | `Assoc(items) =>
      let f = (res, (key, value)) =>
        switch (res, value) {
        | (Ok(res), `String(value)) =>
          Ok(Astring.String.Map.add(key, Config.Value.v(value), res))
        | _ => Error("expected a string value")
        };
      List.fold_left(f, Ok(Astring.String.Map.empty), items);
    | _ => Error("expected an object")
    };
  let to_yojson = (env: t) => {
    let f = (k, v, items) => [(k, Config.Value.to_yojson(v)), ...items];
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
  build: list(list(Config.Value.t)),
  install: list(list(Config.Value.t)),
  sourcePath: Config.Value.t,
  env: Env.t,
};

let ofFile = (path: Path.t) => {
  let%bind data = Run.read(path);
  let json = Yojson.Safe.from_string(data);
  switch (of_yojson(json)) {
  | Ok(task) => Ok(task)
  | Error(err) => Error(`Msg(err))
  };
};
