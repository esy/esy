/** Configuration for esy installer */

type t = {
  esySolveCmd: Cmd.t,
  sourceArchivePath: option(Path.t),
  sourceFetchPath: Path.t,
  sourceStagePath: Path.t,
  sourceInstallPath: Path.t,
  opamArchivesIndexPath: Path.t,
  npmRegistry: string,
  solveTimeout: float,
  skipRepositoryUpdate: bool,
};

let make:
  (
    ~npmRegistry: string=?,
    ~cachePath: Fpath.t=?,
    ~cacheTarballsPath: Fpath.t=?,
    ~cacheSourcesPath: Fpath.t=?,
    ~solveTimeout: float=?,
    ~esySolveCmd: Cmd.t,
    ~skipRepositoryUpdate: bool,
    unit
  ) =>
  RunAsync.t(t);

let resolvedPrefix: string;

let esyOpamOverrideVersion: string;
