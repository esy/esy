/**

  This module represents the dependency graph with concrete package versions
  which was solved by solver and is ready to be fetched by the package fetcher.


  */
[@deriving yojson]
type t = {
  root,
  buildDependencies: list(root),
}
and root = {
  pkg,
  bag: list(pkg),
}
and pkg = {
  name: string,
  version: PackageInfo.Version.t,
  source: PackageInfo.Source.t,
  /**
   * We store OpamInfo.t as part of the lockfile as we want to lock against:
   *
   *   1. changes in the algo opam->esy conversion
   *   2. changes in esy-opam-override
   *   3. changes in opam repository (yes, it is mutable)
   *
   */
  opam: [@default None] option(PackageInfo.OpamInfo.t),
};
