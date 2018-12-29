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

include S.JSONABLE with type t := t

type mode =
  | Build
  | BuildDev
  | BuildDevForce

val pp_mode : mode Fmt.t
val show_mode : mode -> string

val mode_to_yojson : mode Json.encoder
val mode_of_yojson : mode Json.decoder

(**
  This is a pair of which build command to use ("build" or "buildDev") and
  a specification of what to bring into the build env.
 *)
type build = {
  mode : mode;
  deps : DepSpec.t;
}

type plan = {
  all : mode;
  link : mode;
  root : mode;
}

val plan_to_yojson : plan Json.encoder
val plan_of_yojson : plan Json.decoder

val pp_plan : plan Fmt.t
val show_plan : plan -> string

val classify :
  t
  -> plan
  -> EsyInstall.Solution.t
  -> EsyInstall.Package.t
  -> BuildManifest.t
  -> build * BuildManifest.commands
