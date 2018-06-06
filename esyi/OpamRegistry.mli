val versions :
  cfg:Config.t
  -> string
  -> (OpamVersion.Version.t * OpamFile.ThinManifest.t) list RunAsync.t

val version :
    cfg:Config.t
    -> opamOverrides:OpamOverrides.t
    -> string
    -> OpamVersion.Version.t
    -> OpamFile.manifest option RunAsync.t
