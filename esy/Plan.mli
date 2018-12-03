(** An expression to specify a set of packages. *)
module DepSpec : sig

  type id
  (** Package id. *)

  val root : id
  val self : id

  type t
  (** Dependency expression, *)

  val package : id -> t
  (** [package id] refers to a package by its [id]. *)

  val dependencies : id -> t
  (** [dependencies id] refers all dependencies of the package with [id]. *)

  val devDependencies : id -> t
  (** [dependencies id] refers all devDependencies of the package with [id]. *)

  val (+) : t -> t -> t
  (** [a + b] refers to all packages in [a] and in [b]. *)

  val compare : t -> t -> int
  val pp : t Fmt.t
end

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
    scope : Scope.t;
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

val allTasks : t -> Task.t list

val make : ?forceImmutable : bool -> Sandbox.t -> t Run.t

val shell :
  Sandbox.t
  -> EsyInstall.PackageId.t
  -> Unix.process_status RunAsync.t
(** [shell task ()] shells into [task]'s build environment. *)

val exec :
  Sandbox.t
  -> EsyInstall.PackageId.t
  -> Cmd.t
  -> Unix.process_status RunAsync.t
(** [exec task cmd ()] executes [cmd] command in a [task]'s build environment. *)

val build :
  force:bool
  -> ?quiet:bool
  -> ?buildOnly:bool
  -> ?logPath:Path.t
  -> Sandbox.t
  -> t
  -> EsyInstall.PackageId.t
  -> unit RunAsync.t
(** [build task ()] builds the [task]. *)

val buildRoot :
  ?quiet:bool
  -> ?buildOnly:bool
  -> Sandbox.t
  -> t
  -> unit RunAsync.t

val buildDependencies :
  ?concurrency:int
  -> buildLinked:bool
  -> Sandbox.t
  -> t
  -> EsyInstall.PackageId.t
  -> unit RunAsync.t

val isBuilt :
  Sandbox.t
  -> Task.t
  -> bool RunAsync.t

val makeEnv :
  buildIsInProgress:bool
  -> includeCurrentEnv:bool
  -> includeBuildEnv:bool
  -> includeNpmBin:bool
  -> depspec:DepSpec.t
  -> envspec:DepSpec.t
  -> Sandbox.t
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
