/** Configuration for esy installer */

type checkoutCfg = [
  | `Local(Path.t)
  | `Remote(string)
  | `RemoteLocal(string, Path.t)
];

let checkoutCfg_to_yojson: Json.encoder(checkoutCfg);
let pp_checkoutCfg: Fmt.t(checkoutCfg);
let show_checkoutCfg: checkoutCfg => string;

type t =
  pri {
    installCfg: EsyFetch.Config.t,
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
  | Remote(string, Path.t);

let pp: Fmt.t(t);
let show: t => string;
let show_checkout: checkout => string;

let make:
  (
    ~npmRegistry: string=?,
    ~prefixPath: Fpath.t=?,
    ~cacheTarballsPath: Fpath.t=?,
    ~cacheSourcesPath: Fpath.t=?,
    ~fetchConcurrency: int=?,
    ~opamRepository: checkoutCfg=?,
    ~esyOpamOverride: checkoutCfg=?,
    ~opamRepositoryLocal: Fpath.t=?,
    ~opamRepositoryRemote: string=?,
    ~esyOpamOverrideLocal: Fpath.t=?,
    ~esyOpamOverrideRemote: string=?,
    ~solveTimeout: float=?,
    ~esySolveCmd: Cmd.t,
    ~skipRepositoryUpdate: bool,
    unit
  ) =>
  RunAsync.t(t);

let esyOpamOverrideVersion: string;
