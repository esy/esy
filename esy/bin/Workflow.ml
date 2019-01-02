open Esy

type t = {
  solvespec : EsySolve.SolveSpec.t;
  installspec : EsyInstall.InstallSpec.t;
  buildspec : BuildSpec.t;
  execenvspec : EnvSpec.t;
  commandenvspec : EnvSpec.t;
  buildenvspec : EnvSpec.t;
}

let buildAll = EsyInstall.DepSpec.(dependencies self)
let buildDev = EsyInstall.DepSpec.(dependencies self + devDependencies self)

let default =

  let solvespec = EsySolve.{
    SolveSpec.
    solveDev = DepSpec.(dependencies self + devDependencies self);
    solveAll = DepSpec.(dependencies self);
  } in

  let installspec = EsyInstall.{
    InstallSpec.
    installDev = DepSpec.(dependencies self + devDependencies self);
    installAll = DepSpec.(dependencies self);
  } in

  (* This defines how project is built. *)
  let buildspec = {
    BuildSpec.
    (* build all other packages using "build" command with dependencies in the env *)
    buildAll = buildAll;
    (* build linked packages using "build" command with dependencies in the env *)
    buildDev = Some buildDev;
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
    augmentDeps = Some EsyInstall.DepSpec.(package self + dependencies self + devDependencies self);
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
    augmentDeps = Some EsyInstall.DepSpec.(dependencies self + devDependencies self);
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

  {solvespec; installspec; buildspec; execenvspec; commandenvspec; buildenvspec;}
