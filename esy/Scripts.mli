type t

type script = {
  command : EsyInstall.Package.Command.t;
}

val empty : t
val find : string -> t -> script option

val ofSandbox : EsyInstall.SandboxSpec.t -> t RunAsync.t
