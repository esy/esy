(**
 * This module represents manifests and info which can be parsed out of it.
 *)

open EsyPackageConfig

val ofInstallationLocation :
  Config.t
  -> EsyInstall.Config.t
  -> EsyInstall.Package.t
  -> EsyInstall.Installation.location
  -> (BuildManifest.t option * Fpath.set) RunAsync.t
