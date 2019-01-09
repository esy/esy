open EsyPackageConfig;

module EsyIntrospectionEnv: {let rootPackageConfigPath: string;};

type t;

let make:
  (
    ~sandboxEnv: SandboxEnv.t=?,
    EsyBuildPackage.Config.t,
    EsyInstall.SandboxSpec.t,
    EsyInstall.Config.t,
    EsyInstall.Solution.t,
    EsyInstall.Installation.t
  ) =>
  RunAsync.t((t, Fpath.set));

let renderExpression: (t, Scope.t, string) => Run.t(string);

let configure:
  (
    ~forceImmutable: bool=?,
    EnvSpec.t,
    BuildSpec.t,
    BuildSpec.mode,
    t,
    PackageId.t
  ) =>
  Run.t((Scope.SandboxEnvironment.Bindings.t, Scope.t));

let env:
  (
    ~forceImmutable: bool=?,
    EnvSpec.t,
    BuildSpec.t,
    BuildSpec.mode,
    t,
    PackageId.t
  ) =>
  Run.t(Scope.SandboxEnvironment.Bindings.t);

let exec:
  (EnvSpec.t, BuildSpec.t, BuildSpec.mode, t, PackageId.t, Cmd.t) =>
  RunAsync.t(Unix.process_status);

module Task: {
  type t = {
    idrepr: BuildId.Repr.t,
    pkg: EsyInstall.Package.t,
    scope: Scope.t,
    env: Scope.SandboxEnvironment.t,
    build: list(list(Scope.SandboxValue.t)),
    install: option(list(list(Scope.SandboxValue.t))),
  };

  let installPath: (EsyBuildPackage.Config.t, t) => Path.t;
  let buildPath: (EsyBuildPackage.Config.t, t) => Path.t;
  let sourcePath: (EsyBuildPackage.Config.t, t) => Path.t;

  let to_yojson: Json.encoder(t);
};

module Plan: {
  /** A collection of tasks. */

  type t;

  let spec: t => EsyInstall.Solution.Spec.t;

  let get: (t, PackageId.t) => option(Task.t);
  let getByName: (t, string) => option(Task.t);
  let getByNameVersion: (t, string, Version.t) => option(Task.t);

  let all: t => list(Task.t);
  let mode: t => BuildSpec.mode;
};

let makePlan:
  (~forceImmutable: bool=?, BuildSpec.t, BuildSpec.mode, t) => Run.t(Plan.t);

/** [shell task ()] shells into [task]'s build environment. */

let buildShell:
  (BuildSpec.t, BuildSpec.mode, t, PackageId.t) =>
  RunAsync.t(Unix.process_status);

/** [build task ()] builds the [task]. */

let buildOnly:
  (
    ~force: bool,
    ~quiet: bool=?,
    ~buildOnly: bool=?,
    ~logPath: Path.t=?,
    t,
    Plan.t,
    PackageId.t
  ) =>
  RunAsync.t(unit);

let build:
  (
    ~skipStalenessCheck: bool,
    ~concurrency: int=?,
    ~buildLinked: bool,
    t,
    Plan.t,
    list(PackageId.t)
  ) =>
  RunAsync.t(unit);

let buildRoot:
  (~quiet: bool=?, ~buildOnly: bool=?, t, Plan.t) => RunAsync.t(unit);

let isBuilt: (t, Task.t) => RunAsync.t(bool);

let exportBuild:
  (EsyBuildPackage.Config.t, ~outputPrefixPath: Fpath.t, Fpath.t) =>
  RunAsync.t(unit);

let importBuild: (Path.t, Path.t) => RunAsync.t(unit);
