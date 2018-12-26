open Esy

type t = {
  buildspecForDev : BuildSpec.t;
  buildspecForRelease : BuildSpec.t;
  execenvspec : EnvSpec.t;
  commandenvspec : EnvSpec.t;
  buildenvspec : EnvSpec.t;
}

let defaultDepspec = DepSpec.(dependencies self)
let defaultDepspecForLink = DepSpec.(dependencies self)
let defaultDepspecForRoot = DepSpec.(dependencies self)

let default =

  (* This defines how project is built. *)
  let buildspecForDev = {
    BuildSpec.
    (* build all other packages using "build" command with dependencies in the env *)
    build = {mode = Build; deps = defaultDepspec};
    (* build linked packages using "buildDev" command with dependencies in the env *)
    buildLink = Some {mode = BuildDev; deps = defaultDepspecForLink};
    (* build linked packages using "buildDev" command with dependencies in the env *)
    buildRoot = Some {mode = BuildDev; deps = defaultDepspecForRoot};
  } in

  let buildspecForRelease =
    let build = {BuildSpec.mode = Build; deps = defaultDepspec} in
    {
      BuildSpec.
      build = build;
      buildLink = Some build;
      buildRoot = Some build;
    }
  in

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

  {buildspecForDev; buildspecForRelease; execenvspec; commandenvspec; buildenvspec;}
