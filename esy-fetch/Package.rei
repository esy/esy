open EsyPackageConfig;

type t = {
  id: PackageId.t,
  name: string,
  version: Version.t,
  source: PackageSource.t,
  overrides: Overrides.t,
  dependencies: PackageId.Set.t,
  devDependencies: PackageId.Set.t,
  installConfig: InstallConfig.t,
  extraSources: list(ExtraSource.t),
};

let id: t => PackageId.t;
let extraSources: t => list(ExtraSource.t);
let opam: t => RunAsync.t(option((string, Version.t, OpamFile.OPAM.t)));

include S.COMPARABLE with type t := t;
include S.PRINTABLE with type t := t;

module Map: Map.S with type key := t;
module Set: Set.S with type elt := t;
