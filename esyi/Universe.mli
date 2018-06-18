type t
type univ = t

val empty : t
val add : pkg:Package.t -> t -> t

val mem : pkg:Package.t -> t -> bool

val findVersions : name:string -> t -> Package.t list
val findVersion : name:string -> version:PackageInfo.Version.t -> t -> Package.t option
val findVersionExn : name:string -> version:PackageInfo.Version.t -> t -> Package.t

module CudfMapping : sig
  type t

  val encodePkg : Package.t -> t -> Cudf.package option
  val encodePkgExn : Package.t -> t -> Cudf.package

  val decodePkg : Cudf.package -> t -> Package.t option
  val decodePkgExn : Cudf.package -> t -> Package.t

  val univ : t -> univ
  val cudfUniv : t -> Cudf.universe

end

val toCudf : t -> Cudf.universe * CudfMapping.t
