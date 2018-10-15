module Task : sig
  type t = {
    id : string;
    pkgId : EsyInstall.PackageId.t;
    name : string;
    version : EsyInstall.Version.t;
    env : Scope.SandboxEnvironment.t;
    buildCommands : Scope.SandboxValue.t list list;
    installCommands : Scope.SandboxValue.t list list;
    buildType : BuildManifest.BuildType.t;
    sourceType : BuildManifest.SourceType.t;
    sourcePath : Scope.SandboxPath.t;
    buildScope : Scope.t;
    exportedScope : Scope.t;
    platform : System.Platform.t;
  }

  val installPath : t -> Scope.SandboxPath.t

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
  -> buildConfig:Scope.SandboxValue.ctx
  -> sandboxEnv:BuildManifest.Env.item StringMap.t
  -> solution:EsyInstall.Solution.t
  -> installation:EsyInstall.Installation.t
  -> unit
  -> (t * FileInfo.t list) RunAsync.t

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
  -> ?logPath:Scope.SandboxPath.t
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

val buildEnv : t -> Task.t -> Scope.SandboxEnvironment.Bindings.t Run.t
val commandEnv : t -> Task.t -> Scope.SandboxEnvironment.Bindings.t Run.t
val execEnv : t -> Task.t -> Scope.SandboxEnvironment.Bindings.t Run.t

val exportBuild :
  buildConfig:EsyBuildPackage.Config.t
  -> outputPrefixPath:Fpath.t
  -> Fpath.t
  -> unit RunAsync.t

val importBuild :
  buildConfig:EsyBuildPackage.Config.t
  -> Fpath.t
  -> unit RunAsync.t
