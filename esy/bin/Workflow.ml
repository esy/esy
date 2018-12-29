open Esy

type t = {
  solvespec : EsySolve.SolveSpec.t;
  buildspec : BuildSpec.t;
  execenvspec : EnvSpec.t;
  commandenvspec : EnvSpec.t;
  buildenvspec : EnvSpec.t;
} [@@deriving yojson]

let defaultDepspec = DepSpec.(dependencies self)
let defaultDepspecForLink = DepSpec.(dependencies self)
let defaultDepspecForRootForRelease = DepSpec.(dependencies self)
let defaultDepspecForRootForDev = DepSpec.(dependencies self + devDependencies self)

let defaultPlanForRelease = {
  BuildSpec.
  all = Build;
  link = Build;
  root = Build;
}

let defaultPlanForDev = {
  BuildSpec.
  all = Build;
  link = Build;
  root = BuildDev;
}

let defaultPlanForDevForce = {
  BuildSpec.
  all = Build;
  link = Build;
  root = BuildDevForce;
}

let default =

  let solvespec = EsySolve.{
    SolveSpec.
    solveRoot = DepSpec.(dependencies self + devDependencies self);
    solveLink = DepSpec.(dependencies self);
    solveAll = DepSpec.(dependencies self);
  } in

  (* This defines how project is built. *)
  let buildspec = {
    BuildSpec.
    (* build all other packages using "build" command with dependencies in the env *)
    build = defaultDepspec;
    (* build linked packages using "build" command with dependencies in the env *)
    buildLink = Some defaultDepspecForLink;

    buildRootForRelease = Some defaultDepspecForRootForRelease;
    buildRootForDev = Some defaultDepspecForRootForDev;
  } in

  (* This defines environment for "esy x CMD" invocation. *)
  let execenvspec = {
    EnvSpec.
    buildIsInProgress = false;
    includeCurrentEnv = true;
    includeBuildEnv = false;
    includeEsyIntrospectionEnv = true;
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
    includeEsyIntrospectionEnv = true;
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
    includeEsyIntrospectionEnv = false;
    includeNpmBin = false;
    (* This means that environment is the same as in buildspec. *)
    augmentDeps = None;
  } in

  {solvespec; buildspec; execenvspec; commandenvspec; buildenvspec;}
