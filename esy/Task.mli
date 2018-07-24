(**
 * Task represent a set of command and an environment to produce a package
 * build.
 *)

module CommandList : sig
  type t

  val show : t -> string
end

type t = {
  id : string;
  pkg : Package.t;

  buildCommands : CommandList.t;
  installCommands : CommandList.t;

  env : Environment.Closed.t;
  globalEnv : Environment.binding list;
  localEnv : Environment.binding list;
  paths : paths;

  sourceType : Manifest.SourceType.t;

  dependencies : dependency list;

  renderCommandExpr : string -> string Run.t;
}
[@@deriving (show, eq, ord)]

and paths = {
  rootPath : Config.ConfigPath.t;
  sourcePath : Config.ConfigPath.t;
  buildPath : Config.ConfigPath.t;
  buildInfoPath : Config.ConfigPath.t;
  stagePath : Config.ConfigPath.t;
  installPath : Config.ConfigPath.t;
  logPath : Config.ConfigPath.t;
}
[@@deriving show]

and dependency =
  | Dependency of t
  | DevDependency of t
  | BuildTimeDependency of t
[@@deriving (show, eq, ord)]

val isRoot : cfg:Config.t -> t -> bool
val isBuilt : cfg:Config.t -> t -> bool RunAsync.t

val buildEnv : Package.t -> Environment.binding list Run.t
val commandEnv : Package.t -> Environment.binding list Run.t
val sandboxEnv : Package.t -> Environment.binding list Run.t

val ofPackage :
  ?includeRootDevDependenciesInEnv:bool ->
  ?overrideShell:bool ->
  ?forceImmutable:bool ->
  ?system:System.Platform.t ->
  ?initTerm:string option ->
  ?initPath:string ->
  ?initManPath:string ->
  ?initCamlLdLibraryPath:string ->
  ?finalPath:string -> ?finalManPath:string -> Package.t -> t Run.t

val exportBuild : cfg:Config.t -> outputPrefixPath:Path.t -> Path.t -> unit RunAsync.t
val importBuild : Config.t -> Path.t -> unit RunAsync.t

val toBuildProtocolString : ?pretty:bool -> t -> string

val rewritePrefix : cfg:Config.t -> origPrefix:Path.t -> destPrefix:Path.t -> Path.t -> unit RunAsync.t

module DependencyGraph : DependencyGraph.DependencyGraph
  with type node := t
  and type dependency := dependency
