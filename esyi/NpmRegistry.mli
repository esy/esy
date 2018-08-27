type versions = {
  versions : version list;
  distTags : SemverVersion.Version.t StringMap.t;
}
and version = {
  version : SemverVersion.Version.t;
  manifest : Manifest.t;
}

val versions :
  ?fullMetadata:bool
  -> cfg:Config.t
  -> name:string
  -> unit
  -> versions option RunAsync.t

val version :
  cfg:Config.t
  -> name:string
  -> version:SemverVersion.Version.t
  -> unit
  -> Manifest.t RunAsync.t
