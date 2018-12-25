open EsyPackageConfig

type t

type versions = {
  versions : SemverVersion.Version.t list;
  distTags : SemverVersion.Version.t StringMap.t;
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
  -> Package.t RunAsync.t
