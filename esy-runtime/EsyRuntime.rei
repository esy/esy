let currentWorkingDir: Path.t;
let currentExecutable: Path.t;

let version: string;

let env_concurrency: option(int);

let concurrency: option(int) => int;

let getRewritePrefixCommand: unit => RunAsync.t(Cmd.t);
let getEsyBuildPackageCommand: unit => RunAsync.t(Cmd.t);
let getEsySolveCudfCommand: unit => RunAsync.t(Cmd.t);
