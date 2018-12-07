type t

val make :
  ?platform:System.Platform.t
  -> ?sandboxEnv:BuildManifest.Env.t
  -> Config.t
  -> EsyInstall.Solution.t
  -> EsyInstall.Installation.t
  -> (t * Fpath.set) RunAsync.t

val renderExpression : t -> Scope.t -> string -> string Run.t

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

(** This describes how a project should be built. *)
module BuildSpec : sig

  type t = {

    buildLinked : build option;
    (** Optionally define if we need to treat linked packages in a specific way. *)

    buildAll : build;
    (** Define how we treat all other packages. *)
  }

  and build = {
    mode : mode;
    deps : DepSpec.t;
  }
  (**
   * This is a pair of which build command to use ("build" or "buildDev") and
   * a specification of what to bring into the build env.
   *)

  and mode =
    | Build
    | BuildDev

  val pp_mode : mode Fmt.t

  val classify : t -> EsyInstall.Solution.Package.t -> build
end

(** This describes how to construct environment for command invocations. *)
module EnvSpec : sig
  type t = {
    augmentDeps : DepSpec.t option;
    (** Defines what packages we should bring into the command env. *)
    buildIsInProgress : bool;
    (** If we should init the build environment (enable sandboxing, do source relloc). *)
    includeCurrentEnv : bool;
    (** If we should include current environment. *)
    includeBuildEnv : bool;
    (** If we should include the package's build environment. *)
    includeNpmBin : bool;
    (** If we should include the project's npm bin in $PATH. *)
  }
end

val configure :
  ?forceImmutable:bool
  -> EnvSpec.t
  -> BuildSpec.t
  -> t
  -> EsyInstall.PackageId.t
  -> (Scope.SandboxEnvironment.Bindings.t * Scope.t) Run.t

val env :
  ?forceImmutable:bool
  -> EnvSpec.t
  -> BuildSpec.t
  -> t
  -> EsyInstall.PackageId.t
  -> Scope.SandboxEnvironment.Bindings.t Run.t

val exec :
  EnvSpec.t
  -> BuildSpec.t
  -> t
  -> EsyInstall.PackageId.t
  -> Cmd.t
  -> Unix.process_status RunAsync.t

module Task : sig
  type t = {
    pkg : EsyInstall.Solution.Package.t;
    scope : Scope.t;
    env : Scope.SandboxEnvironment.t;
    build : Scope.SandboxValue.t list list;
    install : Scope.SandboxValue.t list list option;
  }

  val installPath : Config.t -> t -> Path.t
  val buildPath : Config.t -> t -> Path.t
  val sourcePath : Config.t -> t -> Path.t

  val to_yojson : t Json.encoder
end

module Plan : sig
  type t
  (** A collection of tasks. *)

  val buildspec : t -> BuildSpec.t

  val get : t -> EsyInstall.PackageId.t -> Task.t option
  val getByName : t -> string -> Task.t option
  val getByNameVersion : t -> string -> EsyInstall.Version.t -> Task.t option

  val all : t -> Task.t list
end

val makePlan :
  ?forceImmutable : bool
  -> t
  -> BuildSpec.t
  -> Plan.t Run.t

val buildShell :
  BuildSpec.t
  -> t
  -> EsyInstall.PackageId.t
  -> Unix.process_status RunAsync.t
(** [shell task ()] shells into [task]'s build environment. *)

val build :
  force:bool
  -> ?quiet:bool
  -> ?buildOnly:bool
  -> ?logPath:Path.t
  -> t
  -> Plan.t
  -> EsyInstall.PackageId.t
  -> unit RunAsync.t
(** [build task ()] builds the [task]. *)

val buildRoot :
  ?quiet:bool
  -> ?buildOnly:bool
  -> t
  -> Plan.t
  -> unit RunAsync.t

val buildDependencies :
  ?concurrency:int
  -> buildLinked:bool
  -> t
  -> Plan.t
  -> EsyInstall.PackageId.t
  -> unit RunAsync.t

val isBuilt :
  t
  -> Task.t
  -> bool RunAsync.t

val exportBuild :
  cfg:Config.t
  -> outputPrefixPath:Fpath.t
  -> Fpath.t
  -> unit RunAsync.t

val importBuild :
  cfg:Config.t
  -> Fpath.t
  -> unit RunAsync.t
