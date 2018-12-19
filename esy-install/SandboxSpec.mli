type t = {
  path : Path.t;
  manifest : ManifestSpec.t;
}

include S.PRINTABLE with type t := t
include S.COMPARABLE with type t := t

module Set : Set.S with type elt = t
module Map : Map.S with type key = t

val doesPathReferToConcreteManifest : Path.t -> bool
val isDefault : t -> bool
val projectName : t -> string

val distPath : t -> Path.t
val tempPath : t -> Path.t
val cachePath : t -> Path.t
val storePath : t -> Path.t
val buildPath : t -> Path.t
val installationPath : t -> Path.t
val pnpJsPath : t -> Path.t
val solutionLockPath : t -> Path.t
val binPath : t -> Path.t

val ofPath : Path.t -> t RunAsync.t
