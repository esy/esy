open EsyPackageConfig;

module Path = EsyLib.Path;

module Env = EsyLib.Environment.Make(Config.Value);

[@deriving (yojson, ord)]
type t = {
  id: string,
  name: string,
  version: string,
  sourceType: SourceType.t,
  buildType: BuildType.t,
  build: list(list(Config.Value.t)),
  install: option(list(list(Config.Value.t))),
  sourcePath: Config.Value.t,
  rootPath: Config.Value.t,
  buildPath: Config.Value.t,
  stagePath: Config.Value.t,
  installPath: Config.Value.t,
  env: Env.t,
  jbuilderHackEnabled: bool,
  depspec: string,
};

let ofFile = (path: Path.t) => {
  open EsyLib.Result.Syntax;
  let* data = Run.read(path);
  let json = Yojson.Safe.from_string(data);
  switch (of_yojson(json)) {
  | Ok(plan) => Ok(plan)
  | Error(err) => Error(`Msg(err))
  };
};
