let currentWorkingDir: Path.t;
let currentExecutable: Path.t;

let version: string;

let env_concurrency: option(int);

let concurrency: option(int) => int;
