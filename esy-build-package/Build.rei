/*

   This module provides functions to build tasks and interact with build task
   environment. This implements the core of esy-build-package command.

 */

type t = pri {
  task: Task.t,
  sourcePath: EsyLib.Path.t,
  storePath: EsyLib.Path.t,
  installPath: EsyLib.Path.t,
  stagePath: EsyLib.Path.t,
  buildPath: EsyLib.Path.t,
  lockPath: EsyLib.Path.t,
  infoPath: EsyLib.Path.t,
  env: Bos.OS.Env.t,
  build: list(Cmd.t),
  install: list(Cmd.t),
  sandbox: Sandbox.sandbox,
};

/**

  Build task.

  if [buildOnly] (set to true by default) is set to true then only build
  commands of a task are executed, other install commands are executed too.

  If [force] is (set to false by default) is set to true then all staleness
  checks are not performed and build is executed.

 */
let build:
  (
    ~buildOnly: bool=?,
    ~force: bool=?,
    ~cfg: Config.t,
    Task.t
  ) => Run.t(unit, 'b);

/**

  Run computation with initialized build env.

  Current working dir is changed to a task's build path.

 */
let withBuild:
  (
    ~commit: bool=?,
    ~cfg: Config.t,
    Task.t,
    t => Run.t(unit, 'b)
  ) => Run.t(unit, 'b);

/**

	Run command in the build environment.

 */
let runCommand : (t, Cmd.t) => Run.t(unit, _)

/**

	Run command interactively in the build environment.

 */
let runCommandInteractive : (t, Cmd.t) => Run.t(unit, _)
