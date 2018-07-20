module Path = EsyLib.Path;
module Result = EsyLib.Result;
module Store = EsyLib.Store;
module Let_syntax = Result.Syntax.Let_syntax;

module Cmd = {
  type t = Bos.Cmd.t;
  let pp = (ppf, v) => {
    let v = v |> Bos.Cmd.to_list |> List.map(Filename.quote);
    Fmt.(hbox(list(~sep=sp, string)))(ppf, v);
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
  env: TaskConfig.Env.t,
};

let id = t => t.id;
let name = t => t.name;
let version = t => t.version;

let build = t => t.build;
let install = t => t.install;

let buildType = t => t.buildType;
let sourceType = t => t.sourceType;

let env = t => t.env;

let infoPath = t => t.infoPath;
let sourcePath = t => t.sourcePath;
let stagePath = t => t.stagePath;
let installPath = t => t.installPath;
let buildPath = t => t.buildPath;
let lockPath = t => t.lockPath;

let configure = (config: Config.t, specConfig: TaskConfig.t) => {
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
    id: specConfig.TaskConfig.id,
    name: specConfig.name,
    version: specConfig.version,
    buildType: specConfig.buildType,
    sourceType: specConfig.sourceType,
    installPath: Path.(storePath / Store.installTree / specConfig.id),
    stagePath: Path.(storePath / Store.stageTree / specConfig.id),
    buildPath: Path.(storePath / Store.buildTree / specConfig.id),
    infoPath: Path.(storePath / Store.buildTree / (specConfig.id ++ ".info")),
    lockPath: Path.(storePath / Store.buildTree / (specConfig.id ++ ".lock")),
    sourcePath,
    env,
    install,
    build,
  });
};

let ofFile = (config: Config.t, path: Path.t) =>
  Run.(
    {
      let%bind data = Bos.OS.File.read(path);
      let%bind spec = Json.parseWith(TaskConfig.of_yojson, data);
      let%bind spec = configure(config, spec);
      Ok(spec);
    }
  );

let isRoot = (~config: Config.t, task: t) =>
  Path.equal(config.sandboxPath, task.sourcePath);
