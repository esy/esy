type t

val init : cfg:Config.t -> unit -> t RunAsync.t

val versions :
  t
  -> name : OpamFile.PackageName.t
  -> (OpamVersion.Version.t * OpamFile.ThinManifest.t) list RunAsync.t

val version :
    t
    -> name : OpamFile.PackageName.t
    -> version : OpamVersion.Version.t
    -> OpamFile.manifest option RunAsync.t
