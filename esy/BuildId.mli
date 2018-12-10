open EsyInstall

module Repr : sig
  type t
  include S.JSONABLE with type t := t
end

type t

val make :
  packageId:PackageId.t
  -> build:BuildManifest.t
  -> sourceType:SourceType.t
  -> mode:BuildSpec.mode
  -> platform:System.Platform.t
  -> arch:System.Arch.t
  -> sandboxEnv:BuildManifest.Env.t
  -> dependencies:t list
  -> unit
  -> t * Repr.t

include S.PRINTABLE with type t := t
include S.JSONABLE with type t := t
include S.COMPARABLE with type t := t

module Set : Set.S with type elt := t
