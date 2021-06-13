type disj('a) = list('a);
type conj('a) = list('a);

module Dep: {
  type t = {
    name: string,
    req,
  }
  and req =
    | Npm(SemverVersion.Constraint.t)
    | NpmDistTag(string)
    | Opam(OpamPackageVersion.Constraint.t)
    | Source(SourceSpec.t);

  let pp: Fmt.t(t);
};

module Dependencies: {
  type t =
    | OpamFormula(conj(disj(Dep.t)))
    | NpmFormula(NpmFormula.t);

  include S.PRINTABLE with type t := t;
  include S.COMPARABLE with type t := t;

  let toApproximateRequests: t => list(Req.t);

  let filterDependenciesByName: (~name: string, t) => t;
};

type t = {
  name: string,
  version: Version.t,
  originalVersion: option(Version.t),
  originalName: option(string),
  source: PackageSource.t,
  overrides: Overrides.t,
  dependencies: Dependencies.t,
  devDependencies: Dependencies.t,
  peerDependencies: NpmFormula.t,
  optDependencies: StringSet.t,
  resolutions: Resolutions.t,
  kind,
  installConfig: InstallConfig.t,
  extraSources: list(ExtraSource.t),
}
and kind =
  | Esy
  | Npm;

let isOpamPackageName: string => bool;

let pp: Fmt.t(t);
let compare: (t, t) => int;

let to_yojson: Json.encoder(t);

module Map: Map.S with type key := t;
module Set: Set.S with type elt := t;
