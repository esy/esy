/**

  Fetch & install sandbox solution.

 */;

open EsyPackageConfig;
open EsyPrimitives;

/**
 * Fetch & install solution for the user project (root)
 */
let fetch:
  (
    FetchDepsSubset.t,
    Sandbox.t,
    Solution.t,
    option(string), /* gitUserName */
    option(string)
  ) => /* gitPassword */
  RunAsync.t(unit);

/** Check if the solution is installed. */

let maybeInstallationOfSolution:
  (FetchDepsSubset.t, Sandbox.t, Solution.t) =>
  RunAsync.t(option(Installation.t));

let fetchOverrideFiles:
  (Config.t, SandboxSpec.t, Override.t) => RunAsync.t(list(File.t));
