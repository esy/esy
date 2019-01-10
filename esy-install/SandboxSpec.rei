open EsyPackageConfig;

type t = {
  path: Path.t,
  manifest,
}
and manifest =
  | Manifest(ManifestSpec.t)
  | ManifestAggregate(list(ManifestSpec.t));

include S.JSONABLE with type t := t;
include S.PRINTABLE with type t := t;
include S.COMPARABLE with type t := t;

module Set: Set.S with type elt = t;
module Map: Map.S with type key = t;

let isDefault: t => bool;
let projectName: t => string;

let manifestPaths: t => list(Path.t);
let manifestPath: t => option(Path.t);
let distPath: t => Path.t;
let tempPath: t => Path.t;
let cachePath: t => Path.t;
let storePath: t => Path.t;
let buildPath: t => Path.t;
let installPath: t => Path.t;
let installationPath: t => Path.t;
let pnpJsPath: t => Path.t;
let solutionLockPath: t => Path.t;
let binPath: t => Path.t;

let ofPath: Path.t => RunAsync.t(t);
