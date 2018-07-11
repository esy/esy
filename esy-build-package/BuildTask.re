module Path = EsyLib.Path;
module Result = EsyLib.Result;
module Store = EsyLib.Store;
module Let_syntax = Result.Syntax.Let_syntax;

module SourceType = {
  [@deriving show]
  type t =
    | Immutable
    | Transient;
  let of_yojson = (json: Yojson.Safe.json) =>
    switch (json) {
    | `String("immutable") => Ok(Immutable)
    | `String("transient") => Ok(Transient)
    | _ => Error("invalid buildType")
    };
  let to_yojson = (sourceType: t) =>
    switch (sourceType) {
    | Immutable => `String("immutable")
    | Transient => `String("transient")
    };
};

module BuildType = {
  [@deriving show]
  type t =
    | InSource
    | JbuilderLike
    | OutOfSource;
  let of_yojson = (json: Yojson.Safe.json) =>
    switch (json) {
    | `String("in-source") => Ok(InSource)
    | `String("out-of-source") => Ok(OutOfSource)
    | `String("_build") => Ok(JbuilderLike)
    | _ => Error("invalid buildType")
    };
  let to_yojson = (buildType: t) =>
    switch (buildType) {
    | InSource => `String("in-source")
    | JbuilderLike => `String("_build")
    | OutOfSource => `String("out-of-source")
    };
};

module Cmd = {
  module JsonRepr = {
    [@deriving (of_yojson, to_yojson)]
    type t = list(string);
  };
  type t = Bos.Cmd.t;
  let pp = (ppf, v) => {
    let v = v |> Bos.Cmd.to_list |> List.map(Filename.quote);
    Fmt.(hbox(list(~sep=sp, string)))(ppf, v);
  };
  let show = Bos.Cmd.to_string;
  let of_yojson = (json: Yojson.Safe.json) =>
    Result.(
      {
        let%bind items = JsonRepr.of_yojson(json);
        Ok(Bos.Cmd.of_list(items));
      }
    );
  let to_yojson = (cmd: t) => cmd |> Bos.Cmd.to_list |> JsonRepr.to_yojson;
};

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

[@deriving show]
type t = {
  id: string,
  name: string,
  version: string,
  sourceType: SourceType.t,
  buildType: BuildType.t,
  build: list(Cmd.t),
  install: list(Cmd.t),
  sourcePath: Path.t,
  stagePath: Path.t,
  installPath: Path.t,
  buildPath: Path.t,
  infoPath: Path.t,
  lockPath: Path.t,
  env: Env.t,
};

type spec = t;

module ConfigFile = {
  [@deriving (show, of_yojson, to_yojson)]
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
      let%bind s = PathSyntax.render(lookupVar, s);
      (
        Path.of_string(s): result(Path.t, [ | `Msg(string)]) :>
          Run.t(Path.t, _)
      );
    };
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
    let renderCommands = commands => {
      let renderCommand = s =>
        s |> Result.List.map(~f=render) |> Result.map(Bos.Cmd.of_list);
      Result.List.map(~f=renderCommand, commands);
    };
    let storePath =
      switch (specConfig.sourceType) {
      | Immutable => config.storePath
      | Transient => config.localStorePath
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
      installPath: Path.(storePath / Store.installTree / specConfig.id),
      stagePath: Path.(storePath / Store.stageTree / specConfig.id),
      buildPath: Path.(storePath / Store.buildTree / specConfig.id),
      infoPath:
        Path.(storePath / Store.buildTree / (specConfig.id ++ ".info")),
      lockPath:
        Path.(storePath / Store.buildTree / (specConfig.id ++ ".lock")),
      sourcePath,
      env,
      install,
      build,
    });
  };
};

let ofFile = (config: Config.t, path: Path.t) : Run.t(t, _) =>
  Run.(
    {
      let%bind data = Bos.OS.File.read(path);
      let%bind spec = Json.parseWith(ConfigFile.of_yojson, data);
      let%bind spec = ConfigFile.configure(config, spec);
      Ok(spec);
    }
  );

let isRoot = (~config: Config.t, task: t) =>
  Path.equal(config.sandboxPath, task.sourcePath);
