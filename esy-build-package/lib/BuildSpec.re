[@deriving show]
type sourceType =
  | Immutable
  | Transient
  | Root;

let sourceType_of_yojson = (json: Yojson.Safe.json) =>
  switch json {
  | `String("immutable") => Ok(Immutable)
  | `String("transient") => Ok(Transient)
  | `String("root") => Ok(Root)
  | _ => Error("invalid buildType")
  };

[@deriving show]
type buildType =
  | InSource
  | JbuilderLike
  | OutOfSource;

let buildType_of_yojson = (json: Yojson.Safe.json) =>
  switch json {
  | `String("in-source") => Ok(InSource)
  | `String("out-of-source") => Ok(OutOfSource)
  | `String("_build") => Ok(JbuilderLike)
  | _ => Error("invalid buildType")
  };

module Cmd = {
  module JsonRepr = {
    [@deriving of_yojson]
    type t = list(string);
  };
  type t = Bos.Cmd.t;
  let pp = Bos.Cmd.pp;
  let of_yojson = (json: Yojson.Safe.json) =>
    Result.(
      {
        let%bind items = JsonRepr.of_yojson(json);
        Ok(Bos.Cmd.of_list(items));
      }
    );
};

module Env = {
  type t = Bos.OS.Env.t;
  let pp = (_fmt, _env) => ();
  let of_yojson = (json: Yojson.Safe.json) =>
    switch json {
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
};

[@deriving show]
type t = {
  id: string,
  name: string,
  version: string,
  sourceType,
  buildType,
  build: list(Cmd.t),
  install: list(Cmd.t),
  sourcePath: Path.t,
  stagePath: Path.t,
  installPath: Path.t,
  buildPath: Path.t,
  infoPath: Path.t,
  env: Env.t
};

type spec = t;

module ConfigFile = {
  [@deriving (show, of_yojson)]
  type t = {
    id: string,
    name: string,
    version: string,
    sourceType,
    buildType,
    build: list(Cmd.t),
    install: list(Cmd.t),
    sourcePath: Path.t,
    env: Env.t
  };
  let configure = (config: Config.t, specConfig: t) : Run.t(spec, 'a) => {
    open Result;
    let lookupVar =
      fun
      | "sandbox" => Some(Path.to_string(config.sandboxPath))
      | "store" => Some(Path.to_string(config.storePath))
      | "localStore" => Some(Path.to_string(config.localStorePath))
      | _ => None;
    let render = s => PathSyntax.render(lookupVar, s);
    let renderPath = s => {
      let s = Path.to_string(s);
      let%bind s = PathSyntax.render(lookupVar, s);
      Path.of_string(s);
    };
    let renderCommand = s =>
      s
      |> Bos.Cmd.to_list
      |> Result.listMap(render)
      |> Result.map(Bos.Cmd.of_list);
    let renderEnv = env => {
      let f = (k, v) =>
        fun
        | Ok(result) => {
            let%bind v = render(v);
            Ok(Astring.String.Map.add(k, v, result));
          }
        | error => error;
      Astring.String.Map.fold(f, env, Ok(Astring.String.Map.empty));
    };
    let renderCommands = commands => Result.listMap(renderCommand, commands);
    let storePath =
      switch specConfig.sourceType {
      | Immutable => config.storePath
      | Transient
      | Root => config.localStorePath
      };
    let%bind sourcePath = renderPath(specConfig.sourcePath);
    let%bind env = renderEnv(specConfig.env);
    let%bind install = renderCommands(specConfig.install);
    let%bind build = renderCommands(specConfig.build);
    Ok({
      id: specConfig.id,
      name: specConfig.name,
      version: specConfig.version,
      buildType: specConfig.buildType,
      sourceType: specConfig.sourceType,
      installPath: Path.(storePath / Config.storeInstallTree / specConfig.id),
      stagePath: Path.(storePath / Config.storeStageTree / specConfig.id),
      buildPath: Path.(storePath / Config.storeBuildTree / specConfig.id),
      infoPath:
        Path.(storePath / Config.storeBuildTree / (specConfig.id ++ ".info")),
      sourcePath,
      env,
      install,
      build
    });
  };
};

let ofFile = (config: Config.t, path: Path.t) =>
  Run.(
    {
      let%bind data = Bos.OS.File.read(path);
      let%bind spec = Json.parseWith(ConfigFile.of_yojson, data);
      let%bind spec = ConfigFile.configure(config, spec);
      Ok(spec);
    }
  );
