(** This describes how a project should be built. *)

open EsyPackageConfig

type t = {
  (**
    Define how we build packages.
    *)
  build : DepSpec.t;

  (**
    Optionally define if we need to treat linked packages in a specific way.

    (this overrides buildLink and build)
    *)
  buildLink : DepSpec.t option;

  (**
    Optionally define if we need to treat the root package in a specific way.

    (this overrides buildLink and build)
    *)
  buildRootForRelease : DepSpec.t option;
  buildRootForDev : DepSpec.t option;
}

(**
  This is a pair of which build command to use ("build" or "buildDev") and
  a specification of what to bring into the build env.
 *)
type build = {
  mode : mode;
  deps : DepSpec.t;
}

and mode =
  | Build
  | BuildDev

val pp_mode : mode Fmt.t
val show_mode : mode -> string
val mode_to_yojson : mode Json.encoder
val mode_of_yojson : mode Json.decoder

val classify :
  t
  -> mode
  -> EsyInstall.Solution.t
  -> EsyInstall.Package.t
  -> BuildManifest.t
  -> build * BuildManifest.commands
