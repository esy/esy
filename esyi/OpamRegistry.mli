val versions :
  cfg:Config.t
  -> OpamFile.PackageName.t
  -> (OpamVersion.Version.t * OpamFile.ThinManifest.t) list RunAsync.t

val version :
    cfg:Config.t
    -> opamOverrides:OpamOverrides.t
    -> OpamFile.PackageName.t
    -> OpamVersion.Version.t
    -> OpamFile.manifest option RunAsync.t
