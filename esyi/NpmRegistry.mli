type t

type versions = {
  versions : version list;
  distTags : SemverVersion.Version.t StringMap.t;
}
and version = {
  version : SemverVersion.Version.t;
  manifest : Manifest.t;
}

val make :
  ?concurrency:int
  -> ?url:string
  -> unit
  -> t

val versions :
  ?fullMetadata:bool
  -> name:string
  -> t
  -> unit
  -> versions option RunAsync.t

val package :
  name:string
  -> version:SemverVersion.Version.t
  -> t
  -> unit
  -> Manifest.t RunAsync.t
