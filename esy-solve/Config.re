[@deriving (show, to_yojson)]
type checkoutCfg = [
  | `Local(Path.t)
  | `Remote(string)
  | `RemoteLocal(string, Path.t)
];

[@deriving show]
type t = {
  installCfg: EsyInstall.Config.t,
  esySolveCmd: Cmd.t,
  esyOpamOverride: checkout,
  opamRepository: checkout,
  npmRegistry: string,
  solveTimeout: float,
  skipRepositoryUpdate: bool,
}
and checkout =
  | Local(Path.t)
  | Remote(string, Path.t);

let esyOpamOverrideVersion = "6";

let configureCheckout = (~defaultRemote, ~defaultLocal) =>
  fun
  | Some(`RemoteLocal(remote, local)) => Remote(remote, local)
  | Some(`Remote(remote)) => Remote(remote, defaultLocal)
  | Some(`Local(local)) => Local(local)
  | None => Remote(defaultRemote, defaultLocal);

let make =
    (
      ~npmRegistry=?,
      ~prefixPath=?,
      ~cacheTarballsPath=?,
      ~cacheSourcesPath=?,
      ~opamRepository=?,
      ~esyOpamOverride=?,
      ~solveTimeout=60.0,
      ~esySolveCmd,
      ~skipRepositoryUpdate,
      (),
    ) => {
  open RunAsync.Syntax;
  let%bind prefixPath =
    RunAsync.ofRun(
      Run.Syntax.(
        switch (prefixPath) {
        | Some(prefixPath) => return(prefixPath)
        | None =>
          let userDir = Path.homePath();
          return(Path.(userDir / ".esy"));
        }
      ),
    );

  let opamRepository = {
    let defaultRemote = "https://github.com/ocaml/opam-repository";
    let defaultLocal = Path.(prefixPath / "opam-repository");
    configureCheckout(~defaultLocal, ~defaultRemote, opamRepository);
  };

  let esyOpamOverride = {
    let defaultRemote = "https://github.com/esy-ocaml/esy-opam-override";
    let defaultLocal = Path.(prefixPath / "esy-opam-override");
    configureCheckout(~defaultLocal, ~defaultRemote, esyOpamOverride);
  };

  let npmRegistry =
    Option.orDefault(~default="http://registry.npmjs.org/", npmRegistry);

  let%bind installCfg =
    EsyInstall.Config.make(
      ~prefixPath,
      ~cacheTarballsPath?,
      ~cacheSourcesPath?,
      (),
    );

  return({
    installCfg,
    esySolveCmd,
    opamRepository,
    esyOpamOverride,
    npmRegistry,
    skipRepositoryUpdate,
    solveTimeout,
  });
};
