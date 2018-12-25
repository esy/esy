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
val add : pkg:InstallManifest.t -> t -> t

(** Check if the package is a member of the package universe. *)
val mem : pkg:InstallManifest.t -> t -> bool

(** Find all versions of a package specified by name. *)
val findVersions : name:string -> t -> InstallManifest.t list

(** Find a specific version of a package. *)
val findVersion : name:string -> version:Version.t -> t -> InstallManifest.t option
val findVersionExn : name:string -> version:Version.t -> t -> InstallManifest.t

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

  val encodePkg : InstallManifest.t -> t -> Cudf.package option
  val encodePkgExn : InstallManifest.t -> t -> Cudf.package

  val decodePkg : Cudf.package -> t -> InstallManifest.t option
  val decodePkgExn : Cudf.package -> t -> InstallManifest.t

  val univ : t -> univ
  val cudfUniv : t -> Cudf.universe
end

(**
 * Encode universe as CUDF>
 *)
val toCudf :
  ?installed:InstallManifest.Set.t
  -> t
  -> Cudf.universe * CudfMapping.t
