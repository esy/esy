module SandboxPath : module type of EsyBuildPackage.Config.Path
module SandboxValue : module type of EsyBuildPackage.Config.Value
module SandboxEnvironment : module type of EsyBuildPackage.Config.Environment

type t

val make :
  platform:System.Platform.t
  -> sandboxEnv:SandboxEnvironment.Bindings.t
  -> id:string
  -> sourceType:BuildManifest.SourceType.t
  -> sourcePath:SandboxPath.t
  -> buildIsInProgress:bool
  -> BuildManifest.t
  -> t
(** An initial scope for the package. *)

val add : direct:bool -> dep:t -> t -> t
(** Add new pkg *)

val storePath : t -> SandboxPath.t
val rootPath : t -> SandboxPath.t
val sourcePath : t -> SandboxPath.t
val buildPath : t -> SandboxPath.t
val buildInfoPath : t -> SandboxPath.t
val stagePath : t -> SandboxPath.t
val installPath : t -> SandboxPath.t
val logPath : t -> SandboxPath.t

val env : includeBuildEnv:bool -> t -> SandboxEnvironment.Bindings.t Run.t

val renderCommandExpr : ?environmentVariableName:string -> t -> string -> string Run.t

val toOpamEnv : ocamlVersion:string option -> t -> OpamFilter.env

val exposeUserEnvWith : (string -> SandboxValue.t -> SandboxValue.t Environment.Binding.t) -> string -> t -> t
