/**

  Fetch & install sandbox solution.

 */;

open EsyPackageConfig;

/**
 * Fetch & install solution for the currently configured sandbox using pnp.js
 * installation strategy.
 */

let fetch:
  (Solution.Spec.t, Sandbox.t, Solution.t, option(string), option(string)) =>
  RunAsync.t(unit);

/** Check if the solution is installed. */

let maybeInstallationOfSolution:
  (Solution.Spec.t, Sandbox.t, Solution.t) =>
  RunAsync.t(option(Installation.t));

let fetchOverrideFiles:
  (Config.t, SandboxSpec.t, Override.t) => RunAsync.t(list(File.t));
