open EsyInstall
open EsyBuild

type t = {
  solvespec : EsySolve.SolveSpec.t;
  installspec : Solution.Spec.t;
  buildspec : BuildSpec.t;
  execenvspec : EnvSpec.t;
  commandenvspec : EnvSpec.t;
  buildenvspec : EnvSpec.t;
}

val buildAll : Solution.DepSpec.t
val buildDev : Solution.DepSpec.t

val default : t
