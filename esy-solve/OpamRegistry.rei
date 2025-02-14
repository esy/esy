/**
 * API for querying opam registry.
 */;

open EsyPackageConfig;

type t;
type registry;

/** Configure a new opam registry instance. */

let make: (~opamRepository: Config.checkout, ~cfg: Config.t, unit) => t;

/** Return a list of resolutions for a given opam package name. */

let versions:
  (
    ~os: System.Platform.t=?,
    ~arch: System.Arch.t=?,
    ~ocamlVersion: OpamPackageVersion.Version.t=?,
    ~name: OpamPackage.Name.t,
    registry
  ) =>
  RunAsync.t(list(OpamResolution.t));

/** Return an opam manifest for a given opam package name, version. */

let version:
  (~name: OpamPackage.Name.t, ~version: OpamPackage.Version.t, t) =>
  RunAsync.t(option(OpamManifest.t));

/** Git clone the registry if necessary */
let initRegistry: t => RunAsync.t(registry);
