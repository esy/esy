/**

   Configuration for package installation needed to fetch and install the packages of a project.

   [sourceInstallPath] and [sourceStagePath]- final path where the package source will be stored. While fetching a package, network failures and other exceptions could result in an inconsistent state of the source cache store. To ensure a package is fetch successfully, it is first placed sourceStagePath and later moved to sourceInstallPath once we know it's valid.
   [fetchConcurrency] - no of parallel units fetching packages
 */

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
