open Esy

type t = {
  buildspec : BuildSpec.t;
  execenvspec : EnvSpec.t;
  commandenvspec : EnvSpec.t;
  buildenvspec : EnvSpec.t;
}

val defaultDepspec : DepSpec.t
val defaultDepspecForLink : DepSpec.t
val defaultDepspecForRootForDev : DepSpec.t
val defaultDepspecForRootForRelease : DepSpec.t

val defaultPlanForDev : BuildSpec.plan
val defaultPlanForRelease : BuildSpec.plan
val default : t
