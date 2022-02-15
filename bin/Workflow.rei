open EsyPrimitives;
open EsyFetch;
open EsyBuild;
open DepSpec;

type t = {
  solvespec: EsySolve.SolveSpec.t,
  installspec: Solution.Spec.t,
  buildspec: BuildSpec.t,
  execenvspec: EnvSpec.t,
  commandenvspec: EnvSpec.t,
  buildenvspec: EnvSpec.t,
};

let buildAll: FetchDepSpec.t;
let buildDev: FetchDepSpec.t;

let default: t;
