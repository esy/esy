/**
 * Representation of an opam package (opam file, url file, override).
 */;


type t = {
  name: OpamPackage.Name.t,
  version: OpamPackage.Version.t,
  opam: OpamFile.OPAM.t,
  url: option(OpamFile.URL.t),
  override: option(Override.t),
  opamRepositoryPath: option(Path.t),
};

module File: {
  module Cache:
    Memoize.MEMOIZE with
      type key := Path.t and type value := RunAsync.t(OpamFile.OPAM.t);

  let ofPath:
    (
      ~upgradeIfOpamVersionIsLessThan: OpamVersion.t=?,
      ~cache: Cache.t=?,
      Fpath.t
    ) =>
    RunAsync.t(OpamFile.OPAM.t);
};

let ofString:
  (~name: OpamTypes.name, ~version: OpamTypes.version, string) => Run.t(t);

/** Load opam manifest of path. */

let ofPath:
  (~name: OpamTypes.name, ~version: OpamTypes.version, Path.t) =>
  RunAsync.t(t);
