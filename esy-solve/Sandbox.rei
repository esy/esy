open EsyPackageConfig;

/** Sandbox */;

type t = {
  /*** Configuration. */
  cfg: Config.t,
  spec: EsyFetch.SandboxSpec.t,
  /*** Root package. */
  root: InstallManifest.t,
  /*** A set of resolutions. */
  resolutions: Resolutions.t,
  /*** Resolver associated with a sandbox. */
  resolver: Resolver.t,
};

let make:
  (
    ~os: System.Platform.t=?,
    ~arch: System.Arch.t=?,
    ~gitUsername: option(string),
    ~gitPassword: option(string),
    ~cfg: Config.t,
    EsyFetch.SandboxSpec.t
  ) =>
  RunAsync.t(t);
let digest: (SolveSpec.t, list(OpamRegistry.t), t) => RunAsync.t(Digestv.t);
