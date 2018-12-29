open Esy

type t = {
  solvespec : EsySolve.SolveSpec.t;
  buildspec : BuildSpec.t;
  execenvspec : EnvSpec.t;
  commandenvspec : EnvSpec.t;
  buildenvspec : EnvSpec.t;
}

val defaultDepspec : DepSpec.t
val defaultDepspecForLink : DepSpec.t
val defaultDepspecForRootForDev : DepSpec.t
val defaultDepspecForRootForRelease : DepSpec.t

val defaultPlanForRelease : BuildSpec.plan
val defaultPlanForDev : BuildSpec.plan
val defaultPlanForDevForce : BuildSpec.plan

val default : t
