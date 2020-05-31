/** Configuration for esy installer */

type t =
  pri {
    sourceArchivePath: option(Path.t),
    sourceFetchPath: Path.t,
    sourceStagePath: Path.t,
    sourceInstallPath: Path.t,
    fetchConcurrency: option(int),
  };

let pp: Fmt.t(t);
let show: t => string;

let make:
  (
    ~prefixPath: Fpath.t=?,
    ~cacheTarballsPath: Fpath.t=?,
    ~cacheSourcesPath: Fpath.t=?,
    ~fetchConcurrency: int=?,
    unit
  ) =>
  RunAsync.t(t);
