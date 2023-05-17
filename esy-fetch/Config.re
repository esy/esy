[@deriving show]
type t = {
  sourceArchivePath: option(Path.t),
  sourceFetchPath: Path.t,
  sourceStagePath: Path.t,
  sourceInstallPath: Path.t,
  fetchConcurrency: option(int),
};

let make =
    (
      ~prefixPath=?,
      ~cacheTarballsPath=?,
      ~cacheSourcesPath=?,
      ~fetchConcurrency=?,
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

  let sourcePath =
    switch (cacheSourcesPath) {
    | Some(path) => path
    | None => Path.(prefixPath / "source")
    };
  let* () = Fs.createDir(sourcePath);

  let* sourceArchivePath =
    switch (cacheTarballsPath) {
    | Some(path) =>
      let* () = Fs.createDir(path);
      return(Some(path));
    | None => return(None)
    };

  let sourceFetchPath = Path.(sourcePath / "f");
  let* () = Fs.createDir(sourceFetchPath);

  let sourceStagePath = Path.(sourcePath / "s");
  let* () = Fs.createDir(sourceStagePath);

  let sourceInstallPath = Path.(sourcePath / "i");
  let* () = Fs.createDir(sourceInstallPath);

  return({
    sourceArchivePath,
    sourceFetchPath,
    sourceStagePath,
    sourceInstallPath,
    fetchConcurrency,
  });
};
