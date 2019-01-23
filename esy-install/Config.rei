/** Configuration for esy installer */

type t =
  pri {
    sourceArchivePath: option(Path.t),
    sourceFetchPath: Path.t,
    sourceStagePath: Path.t,
    sourceInstallPath: Path.t,
  };

let pp: Fmt.t(t);
let show: t => string;

let make:
  (
    ~prefixPath: Fpath.t=?,
    ~cacheTarballsPath: Fpath.t=?,
    ~cacheSourcesPath: Fpath.t=?,
    unit
  ) =>
  RunAsync.t(t);
