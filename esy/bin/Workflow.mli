open Esy

type t = {
  buildspec : BuildSpec.t;
  execenvspec : EnvSpec.t;
  commandenvspec : EnvSpec.t;
  buildenvspec : EnvSpec.t;
}

val defaultDepspecForAll : DepSpec.t
val defaultDepspecForLinked : DepSpec.t

val default : t
