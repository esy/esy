open Esy

type t = {
  solvespec : EsySolve.SolveSpec.t;
  buildspec : BuildSpec.t;
  execenvspec : EnvSpec.t;
  commandenvspec : EnvSpec.t;
  buildenvspec : EnvSpec.t;
}

val buildAll : DepSpec.t
val buildDev : DepSpec.t

val default : t
