open DepSpec;
open EsyPackageConfig;

type t = {
  solveDev: SolveDepSpec.t,
  solveAll: SolveDepSpec.t,
};

let eval: (t, InstallManifest.t) => Run.t(InstallManifest.Dependencies.t);
let compare: (t, t) => int;
