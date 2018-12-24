/** Configuration for esy installer */

type t =
  pri {
    installCfg: EsyInstall.Config.t,
    esySolveCmd: Cmd.t,
    esyOpamOverride: checkout,
    opamRepository: checkout,
    npmRegistry: string,
    solveTimeout: float,
    skipRepositoryUpdate: bool,
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

let make:
  (
    ~npmRegistry: string=?,
    ~cachePath: Fpath.t=?,
    ~cacheTarballsPath: Fpath.t=?,
    ~cacheSourcesPath: Fpath.t=?,
    ~opamRepository: checkoutCfg=?,
    ~esyOpamOverride: checkoutCfg=?,
    ~solveTimeout: float=?,
    ~esySolveCmd: Cmd.t,
    ~skipRepositoryUpdate: bool,
    unit
  ) =>
  RunAsync.t(t);

let esyOpamOverrideVersion: string;
