type t = {
  sourceArchivePath: option(Path.t),
  sourceFetchPath: Path.t,
  sourceStagePath: Path.t,
  sourceInstallPath: Path.t,
};

let make = (~cachePath=?, ~cacheTarballsPath=?, ~cacheSourcesPath=?, ()) => {
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

  return({
    sourceArchivePath,
    sourceFetchPath,
    sourceStagePath,
    sourceInstallPath,
  });
};
