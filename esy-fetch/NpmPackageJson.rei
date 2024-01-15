/** Abstract type representing an NPM package's package.json */
type t;

type lifecycle = {
  postinstall: option(string),
  install: option(string),
};

/**

   Returns [t] representing package.json reside at a path.

   Note: if an esy.json is found, it returns [None]

 */
let ofDir: Path.t => RunAsync.t(option(t));

/** Returns [.bin] field as name - command tuples */
let bin: t => list((string, string));

/** returns lifecycle hooks of a package.json. Useful with Option monads. */
let lifecycle: t => option(lifecycle);
