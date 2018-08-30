(**
 * Task represent a set of commands and an environment to produce a package
 * build.
 *)

type t

type dependency =
  | Dependency of t
  | DevDependency of t
  | BuildTimeDependency of t

val pp_dependency : dependency Fmt.t

val id : t -> string
val pkg : t -> Sandbox.pkg
val plan : t -> EsyBuildPackage.Plan.t

val storePath : t -> Sandbox.Path.t
val installPath : t -> Sandbox.Path.t
val buildInfoPath : t -> Sandbox.Path.t
val sourcePath : t -> Sandbox.Path.t
val logPath : t -> Sandbox.Path.t
val rootPath : t -> Sandbox.Path.t
val buildPath : t -> Sandbox.Path.t
val stagePath : t -> Sandbox.Path.t

val sourceType : t -> Manifest.SourceType.t

val dependencies : t -> dependency list

val env : t -> Sandbox.Environment.t

(** Render expression in task scope. *)
val renderExpression : sandbox:Sandbox.t -> task:t -> string -> string Run.t

val isRoot : sandbox:Sandbox.t -> t -> bool
val isBuilt : sandbox:Sandbox.t -> t -> bool RunAsync.t

val buildEnv : t -> Sandbox.Environment.Bindings.t Run.t
val commandEnv : t -> Sandbox.Environment.Bindings.t Run.t
val sandboxEnv : t -> Sandbox.Environment.Bindings.t Run.t

val ofSandbox :
  ?forceImmutable:bool
  -> ?platform:System.Platform.t
  -> Sandbox.t
  -> t Run.t
(** Create task tree of sandbox. *)

val exportBuild : cfg:Config.t -> outputPrefixPath:Path.t -> Path.t -> unit RunAsync.t
val importBuild : Config.t -> Path.t -> unit RunAsync.t

val rewritePrefix : cfg:Config.t -> origPrefix:Path.t -> destPrefix:Path.t -> Path.t -> unit RunAsync.t

module Graph : DependencyGraph.DependencyGraph
  with type node := t
  and type dependency := dependency
