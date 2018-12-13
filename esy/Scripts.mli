type t

type script = {
  command : EsyI.PackageConfig.Command.t;
}

val empty : t
val find : string -> t -> script option

val ofSandbox : EsyI.SandboxSpec.t -> t RunAsync.t
