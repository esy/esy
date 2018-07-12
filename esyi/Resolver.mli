(** Resolution is a pair of a package name and a package version *)
module Resolution : sig
  type t = private {
    name: string;
    version: Package.Version.t
  }

  val pp : t Fmt.t
  val compare : t -> t -> int
  val equal : t -> t -> bool
end

(** Package request resolver *)
type t

(** Make new resolver *)
val make :
  ?ocamlVersion:Package.Version.t
  -> ?opamRegistry:OpamRegistry.t
  -> cfg:Config.t
  -> unit
  -> t RunAsync.t

(**
 * Resolve package request into a list of resolutions
 *)
val resolve :
  ?fullMetadata:bool
  -> name:string
  -> ?spec:Package.VersionSpec.t
  -> t
  -> (Resolution.t list * Package.VersionSpec.t option) RunAsync.t

(**
 * Resolve source spec into source.
 *)
val resolveSource :
  name:string
  -> sourceSpec:Package.SourceSpec.t
  -> t
  -> Package.Source.t RunAsync.t

(** Fetch the package metadata given the resolution. *)
val package :
  resolution:Resolution.t
  -> t
  -> Package.t RunAsync.t
