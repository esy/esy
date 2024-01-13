type t;

type lifecycle = {
  postinstall: option(string),
  install: option(string),
};

let ofDir: Path.t => RunAsync.t(option(t));

let bin: (~sourcePath: Path.t, t) => list((string, Path.t));
let lifecycle: t => option(lifecycle);
