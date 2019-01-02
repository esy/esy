(** This describes how a project should be built. *)

open EsyPackageConfig

type t = {
  (**
    Define how we build packages.
    *)
  buildAll : DepSpec.t;

  (**
    Optionally define if we need to treat linked packages in a specific way.

    (this overrides buildLink and build)
    *)
  buildDev : DepSpec.t option;
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
  -> mode * DepSpec.t * BuildManifest.commands
