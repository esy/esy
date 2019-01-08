/**
 * Package dependency solver.
 */;

/**
 * Solve dependencies for the root
 */

let solve: (SolveSpec.t, Sandbox.t) => RunAsync.t(EsyInstall.Solution.t);
