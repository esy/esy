(** This describes how a project should be built. *)

type t = {
  (**
    Define how we build packages.
    *)
  build : build;

  (**
    Optionally define if we need to treat linked packages in a specific way.

    (this overrides buildLink and build)
    *)
  buildLink : build option;

  (**
    Optionally define if we need to treat the root package in a specific way.

    (this overrides buildLink and build)
    *)
  buildRoot : build option;
}

(**
  This is a pair of which build command to use ("build" or "buildDev") and
  a specification of what to bring into the build env.
 *)
and build = {
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

val classify : t -> EsyInstall.Solution.t -> EsyInstall.Package.t -> build
