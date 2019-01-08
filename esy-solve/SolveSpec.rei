open EsyPackageConfig;

type t = {
  solveDev: DepSpec.t,
  solveAll: DepSpec.t,
};

let eval: (t, InstallManifest.t) => Run.t(InstallManifest.Dependencies.t);
let compare: (t, t) => int;
