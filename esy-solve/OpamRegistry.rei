/**
 * API for querying opam registry.
 */;

type t;

/** Configure a new opam registry instance. */

let make: (~opamRepository: Config.checkout, ~cfg: Config.t, unit) => t;

/** Return a list of resolutions for a given opam package name. */

let versions:
  (~name: OpamPackage.Name.t, t) => RunAsync.t(list(OpamResolution.t));

/** Return an opam manifest for a given opam package name, version. */

let version:
  (~name: OpamPackage.Name.t, ~version: OpamPackage.Version.t, t) =>
  RunAsync.t(option(OpamManifest.t));
