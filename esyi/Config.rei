/** Configuration for esy installer */

type t = {
  basePath: Path.t,
  lockfilePath: Path.t,
  tarballCachePath: Path.t,
  esyOpamOverrideCheckoutPath: Path.t,
  opamRepositoryCheckoutPath: Path.t,
  npmRegistry: string,
};

let make : (
    ~npmRegistry: string=?,
    ~cachePath: Fpath.t=?,
    ~opamRepositoryCheckoutPath: Fpath.t=?,
    ~esyOpamOverrideCheckoutPath: Fpath.t=?,
    Fpath.t
  ) => RunAsync.t(t)

let resolvedPrefix : string;
