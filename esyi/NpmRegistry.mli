val versions :
  ?fullMetadata:bool
  -> cfg:Config.t
  -> name:string
  -> unit
  -> (SemverVersion.Version.t * Manifest.t) list RunAsync.t

val version :
  cfg:Config.t
  -> name:string
  -> version:SemverVersion.Version.t
  -> unit
  -> Manifest.t RunAsync.t
