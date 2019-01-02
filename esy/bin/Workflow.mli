open Esy

type t = {
  solvespec : EsySolve.SolveSpec.t;
  installspec : EsyInstall.InstallSpec.t;
  buildspec : BuildSpec.t;
  execenvspec : EnvSpec.t;
  commandenvspec : EnvSpec.t;
  buildenvspec : EnvSpec.t;
}

val buildAll : EsyInstall.DepSpec.t
val buildDev : EsyInstall.DepSpec.t

val default : t
