/** Configuration for esy installer */

type t = {
  basePath: Path.t,
  lockfilePath: Path.t,
  tarballCachePath: Path.t,
  esyOpamOverridePath: Path.t,
  opamRepositoryPath: Path.t,
  npmRegistry: string,
};

let make : (~npmRegistry: string=?, ~cachePath: Fpath.t=?, Fpath.t) => RunAsync.t(t)
