open Esy

type t = {
  buildspec : BuildSpec.t;
  execenvspec : EnvSpec.t;
  commandenvspec : EnvSpec.t;
  buildenvspec : EnvSpec.t;
}

val defaultDepspec : DepSpec.t
val defaultDepspecForLink : DepSpec.t
val defaultDepspecForRoot : DepSpec.t

val default : t
