type t = BuildManifest.Env.t

val empty : t

val ofSandbox : EsyI.SandboxSpec.t -> t RunAsync.t

include S.JSONABLE with type t := t
