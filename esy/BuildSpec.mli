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

val classify :
  t
  -> mode
  -> EsyInstall.Package.t
  -> BuildManifest.t
  -> mode * EsyInstall.Solution.DepSpec.t * BuildManifest.commands
