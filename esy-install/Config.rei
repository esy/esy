/** Configuration for esy installer */

type t =
  pri {
    sourceArchivePath: option(Path.t),
    sourceFetchPath: Path.t,
    sourceStagePath: Path.t,
    sourceInstallPath: Path.t,
  };

let make:
  (
    ~cachePath: Fpath.t=?,
    ~cacheTarballsPath: Fpath.t=?,
    ~cacheSourcesPath: Fpath.t=?,
    unit
  ) =>
  RunAsync.t(t);
