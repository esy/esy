/**

   NodeModulesLinker adds support for the older node_modules
   linker. PnP is not always a viable option for a project. In such
   cases linking packages in the node_modules folder is necessary.

   Right now,

   Notes:
   1. At the moment, we don't try to know if a package from NPM is an
   Reason/OCaml package  or Javascript. They're both installed to
   node_modules folder. We could later address this by looking into
   the manifest, [package.json], and figure if it's JS package or OCaml/Reason.

   */
open EsyPrimitives;

/**

   Takes [Installation.t], copies only the npm registry packages into
   the node_modules folder. Currently, it does not use any
   {{: https://docs.npmjs.com/cli/v10/commands/npm-install#install-strategy} hoisted installation strategy}

*/
let link:
  (
    ~sandbox: Sandbox.t,
    ~installation: Installation.t,
    ~projectPath: Path.t,
    ~fetchDepsSubset: FetchDepsSubset.t,
    ~solution: Solution.t
  ) =>
  RunAsync.t(unit);
