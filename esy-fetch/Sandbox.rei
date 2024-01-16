/** Describes a project's installation sandbox (ie. source cache/store)

   Contains,
   - [cfg] - See [Config.t]
   - [spec] - See [SandboxSpec.t]

 */
type t =
  pri {
    cfg: Config.t,
    spec: SandboxSpec.t,
  };

let make: (Config.t, SandboxSpec.t) => t;
