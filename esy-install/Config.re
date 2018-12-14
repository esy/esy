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

let resolvedPrefix = "esyi5-";

let esyOpamOverrideVersion = "6";

let make =
    (
      ~npmRegistry=?,
      ~cachePath=?,
      ~cacheTarballsPath=?,
      ~cacheSourcesPath=?,
      ~solveTimeout=60.0,
      ~esySolveCmd,
      ~skipRepositoryUpdate,
      (),
    ) => {
  open RunAsync.Syntax;
  let%bind cachePath =
    RunAsync.ofRun(
      Run.Syntax.(
        switch (cachePath) {
        | Some(cachePath) => return(cachePath)
        | None =>
          let userDir = Path.homePath();
          return(Path.(userDir / ".esy"));
        }
      ),
    );

  let sourcePath =
    switch (cacheSourcesPath) {
    | Some(path) => path
    | None => Path.(cachePath / "source")
    };
  let%bind () = Fs.createDir(sourcePath);

  let%bind sourceArchivePath =
    switch (cacheTarballsPath) {
    | Some(path) =>
      let%bind () = Fs.createDir(path);
      return(Some(path));
    | None => return(None)
    };

  let sourceFetchPath = Path.(sourcePath / "f");
  let%bind () = Fs.createDir(sourceFetchPath);

  let sourceStagePath = Path.(sourcePath / "s");
  let%bind () = Fs.createDir(sourceStagePath);

  let sourceInstallPath = Path.(sourcePath / "i");
  let%bind () = Fs.createDir(sourceInstallPath);

  let opamArchivesIndexPath = Path.(cachePath / "opam-urls.txt");

  let npmRegistry =
    Option.orDefault(~default="http://registry.npmjs.org/", npmRegistry);

  return({
    esySolveCmd,
    sourceArchivePath,
    sourceFetchPath,
    sourceStagePath,
    sourceInstallPath,
    opamArchivesIndexPath,
    npmRegistry,
    skipRepositoryUpdate,
    solveTimeout,
  });
};
