/**
 * This module describes methods which are performed on build tasks through * "esy-build-package" package builder executable.
 */;

/**
 * Build task.
 */

let build:
  (
    ~buildOnly: bool=?,
    ~quiet: bool=?,
    ~logPath: Path.t=?,
    EsyBuildPackage.Config.t,
    EsyBuildPackage.Plan.t
  ) =>
  RunAsync.t(unit);

/*
 * Spawn an interactive shell inside tbuild environment of the task.
 */
let buildShell:
  (EsyBuildPackage.Config.t, EsyBuildPackage.Plan.t) =>
  RunAsync.t(Unix.process_status);

/*
 * Execute a command inside build environment of the task.
 */
let buildExec:
  (EsyBuildPackage.Config.t, EsyBuildPackage.Plan.t, Cmd.t) =>
  RunAsync.t(Unix.process_status);
