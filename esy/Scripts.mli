type t
type script

val empty : t
val find : string -> t -> script option

val render : BuildSandbox.t -> Scope.t -> script -> Cmd.t Run.t

val ofSandbox : EsyInstall.SandboxSpec.t -> t RunAsync.t
