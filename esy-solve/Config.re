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

let configureDeprecatedCheckout = (~defaultRemote, ~defaultLocal) =>
  fun
  | Some(`RemoteLocal(remote, local)) => Remote(remote, local)
  | Some(`Remote(remote)) => Remote(remote, defaultLocal)
  | Some(`Local(local)) => Local(local)
  | None => Remote(defaultRemote, defaultLocal);

let configureCheckout = (~defaultRemote, ~defaultLocal) =>
  fun
  | (None, None) => Remote(defaultRemote, defaultLocal)
  | (None, Some(local)) => Local(local)
  | (Some(remote), None) => Remote(remote, defaultLocal)
  | (Some(remote), Some(local)) => Remote(remote, local);

let make =
    (
      ~npmRegistry=?,
      ~prefixPath=?,
      ~cacheTarballsPath=?,
      ~cacheSourcesPath=?,
      ~fetchConcurrency=?,
      ~opamRepository=?,
      ~esyOpamOverride=?,
      ~opamRepositoryLocal=?,
      ~opamRepositoryRemote=?,
      ~esyOpamOverrideLocal=?,
      ~esyOpamOverrideRemote=?,
      ~solveTimeout=60.0,
      ~esySolveCmd,
      ~skipRepositoryUpdate,
      (),
    ) => {
  open RunAsync.Syntax;
  let* prefixPath =
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

    switch (opamRepositoryRemote, opamRepositoryLocal) {
    /***
      * If no opamRepositoryRemote nor opamRepositoryLocal options are provided,
      * we fallback to the deprecated opamRepository option.
     */
    | (None, None) =>
      configureDeprecatedCheckout(
        ~defaultRemote,
        ~defaultLocal,
        opamRepository,
      )
    | _ =>
      configureCheckout(
        ~defaultLocal,
        ~defaultRemote,
        (opamRepositoryRemote, opamRepositoryLocal),
      )
    };
  };

  let esyOpamOverride = {
    let defaultRemote = "https://github.com/esy-ocaml/esy-opam-override";
    let defaultLocal = Path.(prefixPath / "esy-opam-override");

    switch (esyOpamOverrideRemote, esyOpamOverrideLocal) {
    /***
      * If no esyOpamOverrideRemote nor esyOpamOverrideLocal options are provided,
      * we fallback to the deprecated esyOpamOverride option.
     */
    | (None, None) =>
      configureDeprecatedCheckout(
        ~defaultRemote,
        ~defaultLocal,
        esyOpamOverride,
      )
    | _ =>
      configureCheckout(
        ~defaultLocal,
        ~defaultRemote,
        (esyOpamOverrideRemote, esyOpamOverrideLocal),
      )
    };
  };

  let npmRegistry =
    Option.orDefault(~default="http://registry.npmjs.org/", npmRegistry);

  let* installCfg =
    EsyInstall.Config.make(
      ~prefixPath,
      ~cacheTarballsPath?,
      ~cacheSourcesPath?,
      ~fetchConcurrency?,
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
