(** This describes how a project should be built. *)

type t = {

  buildLinked : build option;
  (** Optionally define if we need to treat linked packages in a specific way. *)

  buildAll : build;
  (** Define how we treat all other packages. *)
}

and build = {
  mode : mode;
  deps : DepSpec.t;
}
(**
  * This is a pair of which build command to use ("build" or "buildDev") and
  * a specification of what to bring into the build env.
  *)

and mode =
  | Build
  | BuildDev

val pp_mode : mode Fmt.t
val show_mode : mode -> string

val classify : t -> EsyInstall.Solution.Package.t -> build
