(** Package request resolver *)

open EsyPackageConfig

type t

(** Make new resolver *)
val make :
  cfg:Config.t
  -> sandbox:EsyInstall.SandboxSpec.t
  -> unit
  -> t RunAsync.t

val setOCamlVersion : Version.t -> t -> unit
val setResolutions : Resolutions.t -> t -> unit
val getUnusedResolutions : t -> string list



(**
 * Resolve package request into a list of resolutions
 *)
val resolve :
  ?fullMetadata:bool
  -> name:string
  -> ?spec:VersionSpec.t
  -> t
  -> Resolution.t list RunAsync.t

(**
 * Fetch the package metadata given the resolution.
 *
 * This returns an error in not valid package cannot be obtained via resolutions
 * (missing checksums, invalid dependencies format and etc.)
 *)
val package :
  resolution:Resolution.t
  -> t
  -> (InstallManifest.t, string) result RunAsync.t

val versionMatchesReq : t -> Req.t -> string -> Version.t -> bool
val versionMatchesDep : t -> InstallManifest.Dep.t -> string -> Version.t -> bool
