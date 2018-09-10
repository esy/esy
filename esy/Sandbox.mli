(**
 * This represents sandbox.
 *)

module Package : sig
  type t = {
    id : string;
    name : string;
    version : string;
    build : Manifest.Build.t;
    sourcePath : EsyBuildPackage.Config.Path.t;
    originPath : Path.Set.t;
    source : Manifest.Source.t option;
  }

  val pp : t Fmt.t
  val compare : t -> t -> int

  module Map : Map.S with type key = t
end

module Dependency : sig
  type t = (kind * Package.t, error) result

  and kind =
    | Dependency
    | OptDependency
    | DevDependency
    | BuildTimeDependency

  and error =
    | InvalidDependency of { name : string; message : string; }
    | MissingDependency of { name : string; }

  val pp : t Fmt.t
  val compare : t -> t -> int
end


type t = {
  name : string option;
  cfg : Config.t;
  buildConfig: EsyBuildPackage.Config.t;
  root : Package.t;
  dependencies : Dependency.t list Package.Map.t;
  scripts : Manifest.Scripts.t;
  env : Manifest.Env.t;
}

type info = (Path.t * float) list

(** Check if a directory is a sandbox *)
val isSandbox : Path.t -> bool RunAsync.t

(** Init sandbox from given the config *)
val make : cfg:Config.t -> Path.t -> Project.sandbox -> (t * info) RunAsync.t

val init : t -> unit RunAsync.t

val findPackage : (Package.t -> bool) -> t -> Package.t option

val dependencies : Package.t -> t -> Dependency.t list

module Value : module type of EsyBuildPackage.Config.Value
module Environment : module type of EsyBuildPackage.Config.Environment
module Path : module type of EsyBuildPackage.Config.Path
