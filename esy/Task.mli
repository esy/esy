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
val pkg : t -> Package.t
val plan : t -> EsyBuildPackage.Plan.t

val storePath : t -> Config.Path.t
val installPath : t -> Config.Path.t
val buildInfoPath : t -> Config.Path.t
val sourcePath : t -> Config.Path.t
val logPath : t -> Config.Path.t
val rootPath : t -> Config.Path.t
val buildPath : t -> Config.Path.t
val stagePath : t -> Config.Path.t

val sourceType : t -> Manifest.SourceType.t

val dependencies : t -> dependency list

val env : t -> Config.Environment.t

(** Render expression in task scope. *)
val renderExpression : cfg:Config.t -> task:t -> string -> string Run.t

val isRoot : cfg:Config.t -> t -> bool
val isBuilt : cfg:Config.t -> t -> bool RunAsync.t

val buildEnv : t -> Config.Environment.Bindings.t Run.t
val commandEnv : t -> Config.Environment.Bindings.t Run.t
val sandboxEnv : t -> Config.Environment.Bindings.t Run.t

val ofPackage :
  ?forceImmutable:bool ->
  ?platform:System.Platform.t ->
  Package.t -> t Run.t

val exportBuild : cfg:Config.t -> outputPrefixPath:Path.t -> Path.t -> unit RunAsync.t
val importBuild : Config.t -> Path.t -> unit RunAsync.t

val rewritePrefix : cfg:Config.t -> origPrefix:Path.t -> destPrefix:Path.t -> Path.t -> unit RunAsync.t

module Graph : DependencyGraph.DependencyGraph
  with type node := t
  and type dependency := dependency
