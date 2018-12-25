open EsyPackageConfig

(**
 * Package universe holds information about available packages.
 *)

(** Package universe. *)
type t
type univ = t

(** Empty package universe. *)
val empty : Resolver.t -> t

(** Add package to the package universe. *)
val add : pkg:Package.t -> t -> t

(** Check if the package is a member of the package universe. *)
val mem : pkg:Package.t -> t -> bool

(** Find all versions of a package specified by name. *)
val findVersions : name:string -> t -> Package.t list

(** Find a specific version of a package. *)
val findVersion : name:string -> version:Version.t -> t -> Package.t option
val findVersionExn : name:string -> version:Version.t -> t -> Package.t

module CudfName : sig
  type t
  val show : t -> string
  val make : string -> t
end

(**
 * Mapping from universe to CUDF.
 *)
module CudfMapping : sig
  type t

  val encodePkgName : string -> CudfName.t
  val decodePkgName : CudfName.t -> string

  val encodePkg : Package.t -> t -> Cudf.package option
  val encodePkgExn : Package.t -> t -> Cudf.package

  val decodePkg : Cudf.package -> t -> Package.t option
  val decodePkgExn : Cudf.package -> t -> Package.t

  val univ : t -> univ
  val cudfUniv : t -> Cudf.universe
end

(**
 * Encode universe as CUDF>
 *)
val toCudf :
  ?installed:Package.Set.t
  -> t
  -> Cudf.universe * CudfMapping.t
