type t = {
  path : Path.t;
  manifest : manifest;
}

and manifest =
  | Manifest of ManifestSpec.Filename.t
  | ManifestAggregate of ManifestSpec.Filename.t list

include S.PRINTABLE with type t := t
include S.COMPARABLE with type t := t

module Set : Set.S with type elt = t
module Map : Map.S with type key = t

val isDefault : t -> bool
val projectName : t -> string

val manifestPaths : t -> Path.t list
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
