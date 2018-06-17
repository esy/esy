/** Configuration for esy installer */

type t = {
  esySolveCmd: Cmd.t,

  basePath: Path.t,
  lockfilePath: Path.t,
  tarballCachePath: Path.t,

  esyOpamOverride: checkout,
  opamRepository: checkout,
  npmRegistry: string,

  solveTimeout: float,
}

/** This described how a reposoitory should be used */
and checkout =
  | Local(Path.t)
  | Remote(string, Path.t)

and checkoutCfg = [
  | `Local(Path.t)
  | `Remote(string)
  | `RemoteLocal(string, Path.t)
  ];

let make : (
    ~npmRegistry: string=?,
    ~cachePath: Fpath.t=?,
    ~opamRepository: checkoutCfg=?,
    ~esyOpamOverride: checkoutCfg=?,
    ~solveTimeout: float=?,
    ~esySolveCmd: Cmd.t,
    Fpath.t
  ) => RunAsync.t(t)

let resolvedPrefix : string;
