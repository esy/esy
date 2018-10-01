(** Package request resolver *)
type t

(** Make new resolver *)
val make :
  cfg:Config.t
  -> root:Path.t
  -> unit
  -> t RunAsync.t

val setOCamlVersion : Version.t -> t -> unit
val setResolutions : Package.Resolutions.t -> t -> unit

(**
 * Resolve package request into a list of resolutions
 *)
val resolve :
  ?fullMetadata:bool
  -> name:string
  -> ?spec:VersionSpec.t
  -> t
  -> Package.Resolution.t list RunAsync.t

(**
 * Fetch the package metadata given the resolution.
 *
 * This returns an error in not valid package cannot be obtained via resolutions
 * (missing checksums, invalid dependencies format and etc.)
 *)
val package :
  resolution:Package.Resolution.t
  -> t
  -> (Package.t, string) result RunAsync.t

val versionMatchesReq : t -> Req.t -> string -> Version.t -> bool
val versionMatchesDep : t -> Package.Dep.t -> string -> Version.t -> bool
