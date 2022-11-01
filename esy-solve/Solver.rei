/**
 * Package dependency solver.
 */;

/**
 * Solve dependencies for the root
 */

let solve:
  (
    ~gitUsername: option(string),
    ~gitPassword: option(string),
    ~dumpCudfInput: option(EsyLib.DumpToFile.t)=?,
    ~dumpCudfOutput: option(EsyLib.DumpToFile.t)=?,
    SolveSpec.t,
    Sandbox.t
  ) =>
  RunAsync.t(EsyFetch.Solution.t);
