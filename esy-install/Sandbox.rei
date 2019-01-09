type t =
  pri {
    cfg: Config.t,
    spec: SandboxSpec.t,
  };

let make: (Config.t, SandboxSpec.t) => t;
