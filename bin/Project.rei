/**
 * This represents esy project.
 *
 * Project can be in multiple states and in multiple configurations.
 */;

open EsyPrimitives;
open EsyBuild;
open EsyBuild.Scope;
open EsyFetch;

type project = {
  projcfg: ProjectConfig.t,
  spec: SandboxSpec.t,
  workflow: Workflow.t,
  buildCfg: EsyBuildPackage.Config.t,
  solveSandbox: EsySolve.Sandbox.t,
  installSandbox: Sandbox.t,
  scripts: Scripts.t,
  solved: Run.t(solved),
}
and solved = {
  solution: Solution.t,
  fetched: Run.t(fetched),
}
and fetched = {
  installation: Installation.t,
  sandbox: BuildSandbox.t,
  configured: Run.t(configured),
}
and configured = {
  planForDev: BuildSandbox.Plan.t,
  root: BuildSandbox.Task.t,
};

type t = project;

let solved: project => RunAsync.t(solved);
let fetched: project => RunAsync.t(fetched);
let configured: project => RunAsync.t(configured);

let make: ProjectConfig.t => RunAsync.t((project, list(FileInfo.t)));
let write: (project, list(FileInfo.t)) => RunAsync.t(unit);

let plan: (BuildSpec.mode, project) => RunAsync.t(BuildSandbox.Plan.t);

/** Built and installed ocaml package resolved in a project env. */

let ocaml: project => RunAsync.t(Fpath.t);

/** Build & installed ocamlfind package resolved in a project env. */

let ocamlfind: project => RunAsync.t(Fpath.t);

let term: Esy_cmdliner.Term.t(project);
let promiseTerm: Esy_cmdliner.Term.t(RunAsync.t(project));

let withPackage:
  (project, PkgArg.t, Package.t => Lwt.t(Run.t('a))) => RunAsync.t('a);

let buildDependencies:
  (
    ~skipStalenessCheck: bool=?,
    ~buildLinked: bool,
    project,
    BuildSandbox.Plan.t,
    Package.t
  ) =>
  RunAsync.t(unit);

let buildShell:
  (project, BuildSpec.mode, BuildSandbox.t, Package.t) =>
  RunAsync.t(Unix.process_status);

let renderSandboxPath: (SandboxPath.ctx, SandboxPath.t) => Path.t;

let buildPackage:
  (
    ~quiet: bool,
    ~disableSandbox: bool,
    ~buildOnly: bool,
    ProjectConfig.t,
    BuildSandbox.t,
    BuildSandbox.Plan.t,
    Package.t
  ) =>
  RunAsync.t(unit);

let execCommand:
  (
    ~checkIfDependenciesAreBuilt: bool,
    ~buildLinked: bool,
    ~changeDirectoryToPackageRoot: bool=?,
    project,
    EnvSpec.t,
    BuildSpec.mode,
    Package.t,
    Cmd.t
  ) =>
  RunAsync.t(unit);

let printEnv:
  (
    ~name: string=?,
    project,
    EnvSpec.t,
    BuildSpec.mode,
    bool,
    PkgArg.t,
    unit
  ) =>
  RunAsync.t(unit);
