[@deriving (show, to_yojson)]
type checkoutCfg = [
  | `Local(Path.t)
  | `Remote(string)
  | `RemoteLocal(string, Path.t)
];

[@deriving show]
type t = {
  installCfg: EsyFetch.Config.t,
  esySolveCmd: Cmd.t,
  esyOpamOverride: checkout,
  opamRepositories: list(checkout),
  npmRegistry: string,
  solveTimeout: float,
  skipRepositoryUpdate: bool,
}
and checkout =
  | Local(Path.t)
  | Remote(string, option(string), Path.t);

let esyOpamOverrideVersion = "6";

let parseRemote = str => switch(String.split_on_char('#', str)) {
  | [remote, branch] => Ok((remote, Some(branch)))
  | [remote] => Ok((remote, None))
  | _ => Error(`Msg("Internal error: unable to parse " ++ str ++ " into remote and branch"))
}

let configureDeprecatedCheckout = (~defaultRemote, ~defaultLocal) =>
  fun
  | Some(`RemoteLocal(remote, local)) => switch(parseRemote(remote)) {
      | Ok((remote, branchOpt)) => Remote(remote, branchOpt, local)
      | Error(`Msg(msg)) => failwith(msg)
    }
  | Some(`Remote(remote)) => switch(parseRemote(remote)) {
      | Ok((remote, branchOpt)) => Remote(remote, branchOpt, defaultLocal)
      | Error(`Msg(msg)) => failwith(msg)
    }
  | Some(`Local(local)) => Local(local)
  | None => Remote(defaultRemote, None, defaultLocal);

let configureCheckout = (~defaultRemote, ~defaultLocal) =>
  fun
  | (None, None) => Remote(defaultRemote, None, defaultLocal)
  | (None, Some(local)) => Local(local)
  | (Some(remote), None) => switch(parseRemote(remote)) {
      | Ok((remote, branchOpt)) => Remote(remote, branchOpt, defaultLocal)
      | Error(`Msg(msg)) => failwith(msg)
    }
  | (Some(remote), Some(local)) => switch(parseRemote(remote)) {
      | Ok((remote, branchOpt)) => Remote(remote, branchOpt, local)
      | Error(`Msg(msg)) => failwith(msg)
    };

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
      ~opamRepositories,
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

  let opamRepositories =
    List.map(
      ~f=
        opamRepository => {
          let hash = s => s |> Digestv.ofString |> Digestv.toHex;
          switch (opamRepository) {
          | OpamRepository.Remote(location, Some(branch)) => 
            Remote(
              location,
              Some(branch),
              Path.(prefixPath / ("opam-repository-" ++ hash(location ++ branch))),
            );
          | OpamRepository.Remote(location, None) =>
            Remote(
              location,
              None,
              Path.(prefixPath / ("opam-repository-" ++ hash(location))),
            );
          | Local(location) => Local(location)
          }
        },
      opamRepositories,
    );

  let opamRepository = [
    {
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
    },
  ];

  let opamRepositories = opamRepositories @ opamRepository;

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
    EsyFetch.Config.make(
      ~prefixPath,
      ~cacheTarballsPath?,
      ~cacheSourcesPath?,
      ~fetchConcurrency?,
      (),
    );

  return({
    installCfg,
    esySolveCmd,
    opamRepositories,
    esyOpamOverride,
    npmRegistry,
    skipRepositoryUpdate,
    solveTimeout,
  });
};
