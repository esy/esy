(** Package request resolver *)
type t

(** Make new resolver *)
val make :
  cfg:Config.t
  -> sandbox:EsyInstall.SandboxSpec.t
  -> unit
  -> t RunAsync.t

val setOCamlVersion : EsyInstall.Version.t -> t -> unit
val setResolutions : EsyInstall.PackageConfig.Resolutions.t -> t -> unit
val getUnusedResolutions : t -> string list



(**
 * Resolve package request into a list of resolutions
 *)
val resolve :
  ?fullMetadata:bool
  -> name:string
  -> ?spec:EsyInstall.VersionSpec.t
  -> t
  -> EsyInstall.PackageConfig.Resolution.t list RunAsync.t

(**
 * Fetch the package metadata given the resolution.
 *
 * This returns an error in not valid package cannot be obtained via resolutions
 * (missing checksums, invalid dependencies format and etc.)
 *)
val package :
  resolution:EsyInstall.PackageConfig.Resolution.t
  -> t
  -> (Package.t, string) result RunAsync.t

val versionMatchesReq : t -> EsyInstall.Req.t -> string -> EsyInstall.Version.t -> bool
val versionMatchesDep : t -> Package.Dep.t -> string -> EsyInstall.Version.t -> bool
