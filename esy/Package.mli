type t = {
  id : string;
  name : string;
  version : string;
  dependencies : dependencies;
  build : Manifest.Build.t;
  sourcePath : Config.Path.t;
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
    name: string;
    reason: [ | `Reason of string | `Missing ];
  }

val equal : t -> t -> bool
val compare : t -> t -> int
val packageOf : dependency -> t option

module DependencySet : Set.S with type elt = dependency
module Graph : DependencyGraph.DependencyGraph
  with type node = t
  and type dependency := dependency
