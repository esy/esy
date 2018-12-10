open Esy

type t = {
  buildspec : BuildSpec.t;
  execenvspec : EnvSpec.t;
  commandenvspec : EnvSpec.t;
  buildenvspec : EnvSpec.t;
}

let defaultDepspecForAll = DepSpec.(dependencies self)
let defaultDepspecForLinked = DepSpec.(dependencies self)

let default =
  (* This defines how project is built. *)
  let buildspec = {
    BuildSpec.
    (* build linked packages using "buildDev" command with dependencies in the env *)
    buildLinked = Some {mode = BuildDev; deps = defaultDepspecForLinked};
    (* build all other packages using "build" command with dependencies in the env *)
    buildAll = {mode = Build; deps = defaultDepspecForAll};
  } in

  (* This defines environment for "esy x CMD" invocation. *)
  let execenvspec = {
    EnvSpec.
    buildIsInProgress = false;
    includeCurrentEnv = true;
    includeBuildEnv = false;
    includeNpmBin = true;
    (* Environment contains dependencies, devDependencies and package itself. *)
    augmentDeps = Some DepSpec.(package self + dependencies self + devDependencies self);
  } in

  (* This defines environment for "esy CMD" invocation. *)
  let commandenvspec = {
    EnvSpec.
    buildIsInProgress = false;
    includeCurrentEnv = true;
    includeBuildEnv = true;
    includeNpmBin = true;
    (* Environment contains dependencies and devDependencies. *)
    augmentDeps = Some DepSpec.(dependencies self + devDependencies self);
  } in

  (* This defines environment for "esy build CMD" invocation. *)
  let buildenvspec = {
    EnvSpec.
    buildIsInProgress = true;
    includeCurrentEnv = false;
    includeBuildEnv = true;
    includeNpmBin = false;
    (* This means that environment is the same as in buildspec. *)
    augmentDeps = None;
  } in

  {buildspec; execenvspec; commandenvspec; buildenvspec;}
