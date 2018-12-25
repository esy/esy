(** This represents a ref to a package from opam repository. *)

open EsyPackageConfig

type t = PackageSource.opam

val make :
  OpamPackage.Name.t
  -> OpamPackage.Version.t
  -> Path.t
  -> t

val name : t -> string
val version : t -> Version.t
val path : t -> Path.t

val files : t -> File.t list RunAsync.t
val opam : t -> OpamFile.OPAM.t RunAsync.t
val digest : t -> Digestv.t RunAsync.t

include S.JSONABLE with type t := t

