type t = {
  id : string;
  name : string;
  version : string;
  dependencies : dependencies;

  buildCommands : Manifest.commands;
  installCommands : Manifest.commands;
  patches : (Path.t * OpamTypes.filter option) list;
  substs : Path.t list;

  sourcePath : Config.Path.t;
  sourceType : Manifest.SourceType.t;
  buildType : Manifest.BuildType.t;
  sandboxEnv : Manifest.Env.t;
  buildEnv : Manifest.Env.t;
  exportedEnv : Manifest.ExportedEnv.t;
  kind : Manifest.kind;
  resolution : string option;
}

and dependencies =
  dependency list

and dependency =
  | Dependency of t
  | OptDependency of t
  | DevDependency of t
  | BuildTimeDependency of t
  | InvalidDependency of {
    pkgName: string;
    reason: string;
  }

val equal : t -> t -> bool
val compare : t -> t -> int
val packageOf : dependency -> t option

module DependencySet : Set.S with type elt = dependency
module Graph : DependencyGraph.DependencyGraph with type node = t
