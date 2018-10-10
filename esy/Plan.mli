module Task : sig
  type t = {
    id : string;
    pkgId : EsyInstall.PackageId.t;
    name : string;
    version : EsyInstall.Version.t;
    env : Sandbox.Environment.t;
    buildCommands : Sandbox.Value.t list list;
    installCommands : Sandbox.Value.t list list;
    buildType : Manifest.BuildType.t;
    sourceType : Manifest.SourceType.t;
    sourcePath : Sandbox.Path.t;
    buildScope : Scope.t;
    exportedScope : Scope.t;
    platform : System.Platform.t;
  }

  val installPath : t -> Sandbox.Path.t

  val renderExpression :
    buildConfig:EsyBuildPackage.Config.t
    -> t
    -> string
    -> string Run.t

  val to_yojson : t Json.encoder
end

type t
(** A collection of tasks. *)

val findTaskById : t -> EsyInstall.PackageId.t -> Task.t option Run.t
val findTaskByName : t -> string -> Task.t option option
val rootTask : t -> Task.t option

val make :
  platform : System.Platform.t
  -> buildConfig:Sandbox.Value.ctx
  -> sandboxEnv:Manifest.Env.item StringMap.t
  -> solution:EsyInstall.Solution.t
  -> installation:EsyInstall.Installation.t
  -> unit
  -> t RunAsync.t

val shell :
  buildConfig:EsyBuildPackage.Config.t
  -> Task.t
  -> Unix.process_status RunAsync.t
(** [shell task ()] shells into [task]'s build environment. *)

val exec :
  buildConfig:EsyBuildPackage.Config.t
  -> Task.t
  -> Cmd.t
  -> Unix.process_status RunAsync.t
(** [exec task cmd ()] executes [cmd] command in a [task]'s build environment. *)

val build :
  ?force:bool
  -> ?quiet:bool
  -> ?buildOnly:bool
  -> ?logPath:Sandbox.Path.t
  -> buildConfig:EsyBuildPackage.Config.t
  -> Task.t
  -> unit RunAsync.t
(** [build task ()] builds the [task]. *)

val buildDependencies :
  ?concurrency:int
  -> buildConfig:EsyBuildPackage.Config.t
  -> t
  -> EsyInstall.PackageId.t
  -> unit RunAsync.t

val buildEnv : t -> Task.t -> Sandbox.Environment.Bindings.t Run.t
val commandEnv : t -> Task.t -> Sandbox.Environment.Bindings.t Run.t
val execEnv : t -> Task.t -> Sandbox.Environment.Bindings.t Run.t
