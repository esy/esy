/**

  Fetch & install sandbox solution.

 */;

open EsyPrimitives;

/**
 * Fetch & install solution for the user project (root)
 *
 * Store operations
 * - download packages and install them in the store
 * Project operations
 * - create an installation.json
 * - if pnp
 *   - create pnp.js and a node wrapper using it to resolve require()'s
 * - else
 *   - create node_modules folder
 * - create node.js binary wrappers pointing to the correct location (node_modules or directly esy store if pnp is enabled)
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
