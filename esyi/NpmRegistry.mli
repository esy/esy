type t

type versions = {
  versions : EsyInstall.SemverVersion.Version.t list;
  distTags : EsyInstall.SemverVersion.Version.t StringMap.t;
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
  -> version:EsyInstall.SemverVersion.Version.t
  -> t
  -> unit
  -> Package.t RunAsync.t
