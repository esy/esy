(** This describes how to construct environment for command invocations. *)

type t = {
  augmentDeps : DepSpec.t option;
  (** Defines what packages we should bring into the command env. *)
  buildIsInProgress : bool;
  (** If we should init the build environment (enable sandboxing, do source relloc). *)
  includeCurrentEnv : bool;
  (** If we should include current environment. *)
  includeBuildEnv : bool;
  (** If we should include the package's build environment. *)
  includeNpmBin : bool;
  (** If we should include the project's npm bin in $PATH. *)
}
