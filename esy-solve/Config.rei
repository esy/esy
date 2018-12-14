/** Configuration for esy installer */

type t = {
  installCfg: EsyInstall.Config.t,
  esySolveCmd: Cmd.t,
  sourceArchivePath: option(Path.t),
  sourceFetchPath: Path.t,
  sourceStagePath: Path.t,
  sourceInstallPath: Path.t,
  opamArchivesIndexPath: Path.t,
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

let resolvedPrefix: string;

let esyOpamOverrideVersion: string;
