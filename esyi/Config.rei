/** Configuration for esy installer */

type t = {
  esySolveCmd: Cmd.t,

  cacheTarballsPath: Path.t,
  opamArchivesIndexPath: Path.t,

  esyOpamOverride: checkout,
  opamRepository: checkout,
  npmRegistry: string,

  solveTimeout: float,

  skipRepositoryUpdate: bool,

  createProgressReporter:
    (~name: string, unit) => (string => Lwt.t(unit), unit => Lwt.t(unit)),
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
    ~cacheTarballsPath: Fpath.t=?,
    ~opamRepository: checkoutCfg=?,
    ~esyOpamOverride: checkoutCfg=?,
    ~solveTimeout: float=?,
    ~esySolveCmd: Cmd.t,
    ~createProgressReporter:
      (~name: string, unit) => (string => Lwt.t(unit), unit => Lwt.t(unit)),
    ~skipRepositoryUpdate: bool,
    unit
  ) => RunAsync.t(t)

let resolvedPrefix : string;

let esyOpamOverrideVersion : string;
