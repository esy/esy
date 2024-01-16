/**

   Provides routines to download and install a single package.

   Running functions from this module will hit the network.
   Works with a single package. Caller must handle concurrency when
   calling parallely for multiple packages.

 */

/**

   Abstract type representing result of a fetch operation.

   Useful later to install the package. Mostly useful for JS packages,
   since source of native/OCaml packages once fetched and placed in the store
   usually dont need additional installation steps. JS/NPM packages
   have additional installation steps like lifecycle hooks, pnp
   wrapper generation etc.

*/
type kind =
  | Fetched(DistStorage.fetchedDist)
  | Installed(Path.t)
  | Linked(Path.t);

type installation = unit;

let fetch:
  (Sandbox.t, Package.t, option(string), option(string)) => RunAsync.t(kind);

let install:
  (~fetchedKind: kind, ~stagePath: Path.t, Sandbox.t, Package.t) =>
  RunAsync.t(installation);
