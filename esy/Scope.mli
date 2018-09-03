type t

val make :
  platform:System.Platform.t
  -> sandboxEnv:Sandbox.Environment.Bindings.t
  -> id:string
  -> sourceType:Manifest.SourceType.t
  -> buildIsInProgress:bool
  -> Sandbox.Package.t
  -> t
(** An initial scope for the package. *)

val add : direct:bool -> dep:t -> t -> t
(** Add new pkg *)

val storePath : t -> Sandbox.Path.t
val rootPath : t -> Sandbox.Path.t
val sourcePath : t -> Sandbox.Path.t
val buildPath : t -> Sandbox.Path.t
val buildInfoPath : t -> Sandbox.Path.t
val stagePath : t -> Sandbox.Path.t
val installPath : t -> Sandbox.Path.t
val logPath : t -> Sandbox.Path.t

val env : includeBuildEnv:bool -> t -> Sandbox.Environment.Bindings.t Run.t

val renderCommandExpr : ?environmentVariableName:string -> t -> string -> string Run.t

val toOpamEnv : ocamlVersion:string option -> t -> OpamFilter.env

val exposeUserEnvWith : (string -> Sandbox.Value.t -> Sandbox.Value.t Environment.Binding.t) -> string -> t -> t
