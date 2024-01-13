/**

   Provides routines to download and install a single package.

   Running functions from this module will hit the network.
   Works with a single package. Caller must handle concurrency when
   calling parallely for multiple packages.

 */

/**

   Abstract type representing results of a fetch operation.

   Useful later to install the package. Mostly useful for JS packages,
   since native/OCaml packages once fetched and placed in the store
   usually dont need additional installation steps. JS/NPM packages
   have additional installation steps like lifecycle hooks, pnp
   wrapper generation etc.

*/
type fetch;

/* TODO Can we not compute packagejsonpath and install path inside?
   Could it be computed outside and passed to this module's functions */
type installation = {
  pkg: Package.t,
  packageJsonPath: Path.t,
  path: Path.t,
};

let fetch:
  (Sandbox.t, Package.t, option(string), option(string)) =>
  RunAsync.t(fetch);

let install: (Sandbox.t, fetch) => RunAsync.t(installation);
