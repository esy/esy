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

/**

   Returns a list of binaries commands installable by an NPM package
   specified in the [.bin] field.

*/
let bin: t => list((string, Path.t));

/** returns lifecycle hooks of a package.json. Useful with Option monads. */
let lifecycle: t => option(lifecycle);

/** Updates (functional) basePath of [t] */
let setBasePath: (Path.t, t) => t;
