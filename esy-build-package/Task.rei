module Cmd : {
  type t = Bos.Cmd.t;
  let pp: Fmt.t(t);
}

type t

let pp: Fmt.t(t);
let show: t => string;

let id : t => string;
let name : t => string;
let version : t => string;

let build : t => list(Bos.Cmd.t);
let install : t => list(Bos.Cmd.t);

let infoPath : t => EsyLib.Path.t;
let sourcePath : t => EsyLib.Path.t;
let stagePath : t => EsyLib.Path.t;
let installPath : t => EsyLib.Path.t;
let buildPath : t => EsyLib.Path.t;
let lockPath : t => EsyLib.Path.t;

let buildType : t => BuildType.t;
let sourceType : t => SourceType.t;

let env : t => TaskConfig.Env.t

let ofFile :
  (Config.t, Fpath.t)
  => result(t, [> `CommandError(Bos.Cmd.t, Bos.OS.Cmd.status) | `Msg(string) ]);

let isRoot :
  (~config: Config.t, t)
  => bool;
