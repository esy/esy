(**
 * Task represent a set of command and an environment to produce a package
 * build.
 *)

(** This is an abstract type which represents a scope of a task. *)
module Scope : sig
  type t
end

type t = private {
  id : string;
  pkg : Package.t;

  buildCommands : string list list;
  installCommands : string list list;

  env : Environment.Closed.t;
  globalEnv : Environment.binding list;
  localEnv : Environment.binding list;
  paths : paths;

  sourceType : Manifest.SourceType.t;

  dependencies : dependency list;

  platform : System.Platform.t;
  scope : Scope.t;
}

and paths = private {
  rootPath : Config.Path.t;
  sourcePath : Config.Path.t;
  buildPath : Config.Path.t;
  buildInfoPath : Config.Path.t;
  stagePath : Config.Path.t;
  installPath : Config.Path.t;
  logPath : Config.Path.t;
}

and dependency =
  | Dependency of t
  | DevDependency of t
  | BuildTimeDependency of t

(** Render expression in task scope. *)
val renderExpression : cfg:Config.t -> task:t -> string -> string Run.t

val isRoot : cfg:Config.t -> t -> bool
val isBuilt : cfg:Config.t -> t -> bool RunAsync.t

val buildEnv : Package.t -> Environment.binding list Run.t
val commandEnv : Package.t -> Environment.binding list Run.t
val sandboxEnv : Package.t -> Environment.binding list Run.t

val ofPackage :
  ?includeRootDevDependenciesInEnv:bool ->
  ?overrideShell:bool ->
  ?forceImmutable:bool ->
  ?platform:System.Platform.t ->
  ?initTerm:string option ->
  ?initPath:string ->
  ?initManPath:string ->
  ?initCamlLdLibraryPath:string ->
  ?finalPath:string -> ?finalManPath:string -> Package.t -> t Run.t

val exportBuild : cfg:Config.t -> outputPrefixPath:Path.t -> Path.t -> unit RunAsync.t
val importBuild : Config.t -> Path.t -> unit RunAsync.t

val toBuildProtocolString : ?pretty:bool -> t -> string

val rewritePrefix : cfg:Config.t -> origPrefix:Path.t -> destPrefix:Path.t -> Path.t -> unit RunAsync.t

module Graph : DependencyGraph.DependencyGraph
  with type node := t
  and type dependency := dependency
