open EsyInstall

type t

val make :
  sandboxEnv:BuildManifest.Env.t
  -> id:PackageId.t
  -> dist:Dist.t option
  -> build:BuildManifest.t
  -> sourceType:SourceType.t
  -> mode:BuildSpec.mode
  -> dependencies:t list
  -> unit
  -> t

include S.PRINTABLE with type t := t
include S.JSONABLE with type t := t
include S.COMPARABLE with type t := t

module Set : Set.S with type elt := t
