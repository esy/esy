type t

val make :
  ?sandboxEnv:BuildManifest.Env.t
  -> Config.t
  -> EsyInstall.Solution.t
  -> EsyInstall.Installation.t
  -> (t * Fpath.set) RunAsync.t

val renderExpression : t -> Scope.t -> string -> string Run.t

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
    idrepr : BuildId.Repr.t;
    pkg : EsyInstall.Solution.Package.t;
    scope : Scope.t;
    env : Scope.SandboxEnvironment.t;
    build : Scope.SandboxValue.t list list;
    install : Scope.SandboxValue.t list list option;
    dependencies : EsyInstall.PackageId.t list;
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

val buildOnly :
  force:bool
  -> ?quiet:bool
  -> ?buildOnly:bool
  -> ?logPath:Path.t
  -> t
  -> Plan.t
  -> EsyInstall.PackageId.t
  -> unit RunAsync.t
(** [build task ()] builds the [task]. *)

val build :
  ?concurrency:int
  -> buildLinked:bool
  -> t
  -> Plan.t
  -> EsyInstall.PackageId.t list
  -> unit RunAsync.t


val buildRoot :
  ?quiet:bool
  -> ?buildOnly:bool
  -> t
  -> Plan.t
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
