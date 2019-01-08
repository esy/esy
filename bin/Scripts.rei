open EsyPackageConfig;

type t;

type script = {command: Command.t};

let empty: t;
let find: (string, t) => option(script);

let ofSandbox: EsyInstall.SandboxSpec.t => RunAsync.t(t);
