(** This describes how a project should be built. *)

open EsyPackageConfig

type t = EsyInstall.Solution.Spec.t = {
  all : EsyInstall.Solution.DepSpec.t;
  dev : EsyInstall.Solution.DepSpec.t;
}

type mode =
  | Build
  | BuildDev

val pp_mode : mode Fmt.t
val show_mode : mode -> string

val mode_to_yojson : mode Json.encoder
val mode_of_yojson : mode Json.decoder

val mode : mode -> EsyInstall.Package.t -> mode
val depspec : t -> mode -> EsyInstall.Package.t -> EsyInstall.Solution.DepSpec.t
val buildCommands : mode -> EsyInstall.Package.t -> BuildManifest.t -> BuildManifest.commands
