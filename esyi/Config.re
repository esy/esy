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
and checkout =
  | Local(Path.t)
  | Remote(string, Path.t)
and checkoutCfg = [
  | `Local(Path.t)
  | `Remote(string)
  | `RemoteLocal(string, Path.t)
];

let resolvedPrefix = "esyi5-";

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
      ~cachePath=?,
      ~cacheTarballsPath=?,
      ~opamRepository=?,
      ~esyOpamOverride=?,
      ~solveTimeout=8.0,
      ~esySolveCmd,
      ~createProgressReporter,
      ~skipRepositoryUpdate,
      (),
    ) =>
  RunAsync.Syntax.(
    {
      let%bind cachePath =
        RunAsync.ofRun(
          Run.Syntax.(
            switch (cachePath) {
            | Some(cachePath) => return(cachePath)
            | None =>
              let%bind userDir = Path.user();
              return(Path.(userDir / ".esy" / "esyi"));
            }
          ),
        );

      let cacheTarballsPath =
        switch (cacheTarballsPath) {
        | Some(cacheTarballsPath) => cacheTarballsPath
        | None => Path.(cachePath / "tarballs")
        };
      let%bind () = Fs.createDir(cacheTarballsPath);

      let opamArchivesIndexPath = Path.(cachePath / "opam-urls.txt");

      let opamRepository = {
        let defaultRemote = "https://github.com/ocaml/opam-repository";
        let defaultLocal = Path.(cachePath / "opam-repository");
        configureCheckout(~defaultLocal, ~defaultRemote, opamRepository);
      };

      let esyOpamOverride = {
        let defaultRemote = "https://github.com/esy-ocaml/esy-opam-override";
        let defaultLocal = Path.(cachePath / "esy-opam-override");
        configureCheckout(~defaultLocal, ~defaultRemote, esyOpamOverride);
      };

      let npmRegistry =
        Option.orDefault(~default="http://registry.npmjs.org/", npmRegistry);

      return({
        createProgressReporter,
        esySolveCmd,
        cacheTarballsPath,
        opamArchivesIndexPath,
        opamRepository,
        esyOpamOverride,
        npmRegistry,
        skipRepositoryUpdate,
        solveTimeout,
      });
    }
  );
