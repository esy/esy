/** Configuration for esy installer */

type checkoutCfg = [
  | `Local(Path.t)
  | `Remote(string)
  | `RemoteLocal(string, Path.t)
];

let checkoutCfg_to_yojson : Json.encoder(checkoutCfg);
let pp_checkoutCfg : Fmt.t(checkoutCfg);
let show_checkoutCfg : checkoutCfg => string;

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
