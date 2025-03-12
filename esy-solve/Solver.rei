/**
 * Package dependency solver.
 */;

/**
 * Solve dependencies for the root
 */

let solve:
  (
    ~os: System.Platform.t=?,
    ~arch: System.Arch.t=?,
    ~dumpCudfInput: option(EsyLib.DumpToFile.t)=?,
    ~dumpCudfOutput: option(EsyLib.DumpToFile.t)=?,
    ~opamRegistries: list(OpamRegistry.t),
    ~expectedPlatforms: EsyOpamLibs.AvailablePlatforms.t,
    ~gitUsername: option(string),
    ~gitPassword: option(string),
    ~esyFetchSandboxSpec: EsyFetch.SandboxSpec.t,
    SolveSpec.t,
    Sandbox.t
  ) =>
  RunAsync.t(
    (
      EsyFetch.Solution.t,
      EsyOpamLibs.AvailablePlatforms.Map.t(EsyFetch.Solution.t),
    ),
  );
