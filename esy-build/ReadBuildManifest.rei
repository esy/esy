/**
 * This module represents manifests and info which can be parsed out of it.
 */;

open EsyPackageConfig;

let ofInstallationLocation:
  (
    EsyInstall.SandboxSpec.t,
    EsyInstall.Config.t,
    EsyInstall.Package.t,
    EsyInstall.Installation.location
  ) =>
  RunAsync.t((option(BuildManifest.t), Fpath.set));
