(** This describes how to construct environment for command invocations. *)

type t = {
  (**
    Defines what packages we should bring into the command env.
    *)
  augmentDeps : DepSpec.t option;

  (**
    If we should init the build environment (enable sandboxing, do source
    relloc).
    *)
  buildIsInProgress : bool;

  (**
    If we should include current environment.
    *)
  includeCurrentEnv : bool;

  (**
    If we should include the package's build environment.
    *)
  includeBuildEnv : bool;

  (**
    If we should include the project's npm bin in $PATH.
    *)
  includeNpmBin : bool;
}
