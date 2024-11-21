open EsyPackageConfig;

type t = {
  id: PackageId.t,
  name: string,
  version: Version.t,
  source: PackageSource.t,
  overrides: Overrides.t,
  dependencies: PackageId.Set.t,
  devDependencies: PackageId.Set.t,
  installConfig: InstallConfig.t, /* currently only tells if pnp is enabled or not */
  extraSources: list(ExtraSource.t), /* See opam manual */
  available: option(string),
};

let id: t => PackageId.t;
let extraSources: t => list(ExtraSource.t);
let opam: t => RunAsync.t(option((string, Version.t, OpamFile.OPAM.t)));
let evaluateOpamPackageAvailability: t => bool;

include S.COMPARABLE with type t := t;
include S.PRINTABLE with type t := t;

module Map: Map.S with type key := t;
module Set: Set.S with type elt := t;
