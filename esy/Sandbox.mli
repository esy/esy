(**
 * This represents sandbox.
 *)

type t = {
  cfg : Config.t;
  buildConfig: EsyBuildPackage.Config.t;
  root : pkg;
  scripts : Manifest.Scripts.t;
  env : Manifest.Env.t;
}

and pkg = {
  id : string;
  name : string;
  version : string;
  dependencies : dependencies;
  build : Manifest.Build.t;
  sourcePath : EsyBuildPackage.Config.Path.t;
  resolution : string option;
}

and dependencies =
  dependency list

and dependency =
  | Dependency of pkg
  | OptDependency of pkg
  | DevDependency of pkg
  | BuildTimeDependency of pkg
  | InvalidDependency of {
    name: string;
    reason: [ | `Reason of string | `Missing ];
  }

val pp_dependency : dependency Fmt.t
val packageOf : dependency -> pkg option

module PackageGraph : DependencyGraph.DependencyGraph
  with type node = pkg
  and type dependency := dependency

module PackageMap : Map.S with type key = pkg

module DependencySet : Set.S with type elt = dependency
module DependencyMap : Map.S with type key = dependency

type info = (Path.t * float) list

(** Check if a directory is a sandbox *)
val isSandbox : Path.t -> bool RunAsync.t

(** Init sandbox from given the config *)
val make : cfg:Config.t -> Path.t -> Project.sandbox -> (t * info) RunAsync.t

val init : t -> unit RunAsync.t

module Value : module type of EsyBuildPackage.Config.Value
module Environment : module type of EsyBuildPackage.Config.Environment
module Path : module type of EsyBuildPackage.Config.Path
