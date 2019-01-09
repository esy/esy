open EsyInstall;
open EsyBuild;

type t = {
  solvespec: EsySolve.SolveSpec.t,
  installspec: Solution.Spec.t,
  buildspec: BuildSpec.t,
  execenvspec: EnvSpec.t,
  commandenvspec: EnvSpec.t,
  buildenvspec: EnvSpec.t,
};

let buildAll: Solution.DepSpec.t;
let buildDev: Solution.DepSpec.t;

let default: t;
