/**
 * This module represents manifests and info which can be parsed out of it.
 */;

open EsyPackageConfig;

let ofInstallationLocation:
  (
    EsyFetch.SandboxSpec.t,
    EsyFetch.Config.t,
    EsyFetch.Package.t,
    EsyFetch.Installation.location
  ) =>
  RunAsync.t((option(BuildManifest.t), Fpath.set));
