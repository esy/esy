type t = private {
  cfg : Config.t;
  spec : SandboxSpec.t;
}

val make : Config.t -> SandboxSpec.t -> t

