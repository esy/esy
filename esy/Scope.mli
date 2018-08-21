type t

val make :
  platform:System.Platform.t
  -> sandboxEnv:Config.Environment.Bindings.t
  -> id:string
  -> sourceType:Manifest.SourceType.t
  -> buildIsInProgress:bool
  -> Package.t
  -> t
(** An initial scope for the package. *)

val add : direct:bool -> dep:t -> t -> t
(** Add new pkg *)

val storePath : t -> Config.Path.t
val rootPath : t -> Config.Path.t
val sourcePath : t -> Config.Path.t
val buildPath : t -> Config.Path.t
val buildInfoPath : t -> Config.Path.t
val stagePath : t -> Config.Path.t
val installPath : t -> Config.Path.t
val logPath : t -> Config.Path.t

val env : includeBuildEnv:bool -> t -> Config.Environment.Bindings.t Run.t

val renderCommandExpr : ?environmentVariableName:string -> t -> string -> string Run.t

val toOpamEnv : ocamlVersion:string option -> t -> OpamFilter.env

val exposeUserEnvWith : (string -> Config.Value.t -> Config.Value.t Environment.Binding.t) -> string -> t -> t
