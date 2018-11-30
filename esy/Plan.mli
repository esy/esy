module Sandbox : sig
  type t = {
    cfg : Config.t;
    platform : System.Platform.t;
    sandboxEnv : BuildManifest.Env.t;
    solution : EsyInstall.Solution.t;
    installation : EsyInstall.Installation.t;
    manifests : BuildManifest.t EsyInstall.PackageId.Map.t;
  }

  val make :
    ?platform:System.Platform.t
    -> ?sandboxEnv:BuildManifest.Env.t
    -> Config.t
    -> EsyInstall.Solution.t
    -> EsyInstall.Installation.t
    -> (t * Fpath.set) RunAsync.t
end

module Task : sig
  type t = {
    id : string;
    pkg : EsyInstall.Solution.Package.t;
    name : string;
    version : EsyInstall.Version.t;
    env : Scope.SandboxEnvironment.t;
    buildCommands : Scope.SandboxValue.t list list;
    installCommands : Scope.SandboxValue.t list list option;
    buildType : BuildManifest.BuildType.t;
    sourceType : BuildManifest.SourceType.t;
    sourcePath : Scope.SandboxPath.t;
    buildScope : Scope.t;
    exportedScope : Scope.t;
    platform : System.Platform.t;
    manifest : BuildManifest.t;
  }

  val installPath : Config.t -> t -> Path.t
  val buildPath : Config.t -> t -> Path.t
  val sourcePath : Config.t -> t -> Path.t

  val renderExpression :
    cfg:Config.t
    -> t
    -> string
    -> string Run.t

  val to_yojson : t Json.encoder
end

type t
(** A collection of tasks. *)

val findTaskById : t -> EsyInstall.PackageId.t -> Task.t option
val findTaskByName : t -> string -> Task.t option
val findTaskByNameVersion : t -> string -> EsyInstall.Version.t -> Task.t option

val rootTask : t -> Task.t
val allTasks : t -> Task.t list

val make : ?forceImmutable : bool -> Sandbox.t -> t Run.t

val shell :
  cfg:Config.t
  -> Task.t
  -> Unix.process_status RunAsync.t
(** [shell task ()] shells into [task]'s build environment. *)

val exec :
  cfg:Config.t
  -> Task.t
  -> Cmd.t
  -> Unix.process_status RunAsync.t
(** [exec task cmd ()] executes [cmd] command in a [task]'s build environment. *)

val build :
  force:bool
  -> ?quiet:bool
  -> ?buildOnly:bool
  -> ?logPath:Path.t
  -> cfg:Config.t
  -> t
  -> EsyInstall.PackageId.t
  -> unit RunAsync.t
(** [build task ()] builds the [task]. *)

val buildRoot :
  ?quiet:bool
  -> ?buildOnly:bool
  -> cfg:Config.t
  -> t
  -> unit RunAsync.t

val buildDependencies :
  ?concurrency:int
  -> buildLinked:bool
  -> cfg:Config.t
  -> t
  -> EsyInstall.PackageId.t
  -> unit RunAsync.t

val isBuilt :
  cfg:Config.t
  -> Task.t
  -> bool RunAsync.t

val commandEnv :
  Sandbox.t
  -> EsyInstall.PackageId.t
  -> Scope.SandboxEnvironment.Bindings.t Run.t

val execEnv :
  Sandbox.t
  -> EsyInstall.PackageId.t
  -> Scope.SandboxEnvironment.Bindings.t Run.t

val buildEnv :
  Sandbox.t
  -> EsyInstall.PackageId.t
  -> Scope.SandboxEnvironment.Bindings.t Run.t

val exportBuild :
  cfg:Config.t
  -> outputPrefixPath:Fpath.t
  -> Fpath.t
  -> unit RunAsync.t

val importBuild :
  cfg:Config.t
  -> Fpath.t
  -> unit RunAsync.t
