type t = {
  id: string,
  name: string,
  version: string,
  sourceType: EsyLib.SourceType.t,
  buildType: EsyLib.BuildType.t,
  build: list(list(Config.Value.t)),
  install: list(list(Config.Value.t)),
  sourcePath: Config.Value.t,
  env: EsyLib.Environment.Make(Config.Value).t
};

include EsyLib.S.COMPARABLE with type t := t
include EsyLib.S.JSONABLE with type t := t

let ofFile: EsyLib.Path.t => Run.t(t, _);
