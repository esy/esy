open EsyPrimitives;
open EsyInstall;
open EsyBuild;
open DepSpec;

type t = {
  solvespec: EsySolve.SolveSpec.t,
  installspec: Solution.Spec.t,
  buildspec: BuildSpec.t,
  execenvspec: EnvSpec.t,
  commandenvspec: EnvSpec.t,
  buildenvspec: EnvSpec.t,
};

let buildAll = FetchDepSpec.(dependencies(self));
let buildDev = FetchDepSpec.(dependencies(self) + devDependencies(self));

let default = {
  let solvespec =
    EsySolve.{
      SolveSpec.solveDev:
        SolveDepSpec.(dependencies(self) + devDependencies(self)),
      solveAll: SolveDepSpec.(dependencies(self)),
    };

  let installspec = {
    Solution.Spec.dev:
      FetchDepSpec.(dependencies(self) + devDependencies(self)),
    all: FetchDepSpec.(dependencies(self)),
  };

  /* This defines how project is built. */
  let buildspec = {
    BuildSpec.all:
      /* build all other packages using "build" command with dependencies in the env */
      buildAll,
    /* build linked packages using "build" command with dependencies in the env */
    dev: buildDev,
  };

  /* This defines environment for "esy x CMD" invocation. */
  let execenvspec = {
    EnvSpec.buildIsInProgress: false,
    includeCurrentEnv: true,
    includeBuildEnv: false,
    includeEsyIntrospectionEnv: true,
    includeNpmBin: true,
    /* Environment contains dependencies, devDependencies and package itself. */
    augmentDeps:
      Some(
        FetchDepSpec.(
          package(self) + dependencies(self) + devDependencies(self)
        ),
      ),
  };

  /* This defines environment for "esy CMD" invocation. */
  let commandenvspec = {
    EnvSpec.buildIsInProgress: false,
    includeCurrentEnv: true,
    includeBuildEnv: true,
    includeEsyIntrospectionEnv: true,
    includeNpmBin: true,
    /* Environment contains dependencies and devDependencies. */
    augmentDeps:
      Some(FetchDepSpec.(dependencies(self) + devDependencies(self))),
  };

  /* This defines environment for "esy build CMD" invocation. */
  let buildenvspec = {
    EnvSpec.buildIsInProgress: true,
    includeCurrentEnv: false,
    includeBuildEnv: true,
    includeEsyIntrospectionEnv: false,
    includeNpmBin: false,
    /* This means that environment is the same as in buildspec. */
    augmentDeps: None,
  };

  {
    solvespec,
    installspec,
    buildspec,
    execenvspec,
    commandenvspec,
    buildenvspec,
  };
};
