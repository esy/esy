(**
 * This represents sandbox.
 *)

module Package : sig
  type t = {
    id : string;
    name : string;
    version : EsyInstall.Version.t;
    build : Manifest.Build.t;
    originPath : Path.Set.t;
    source : Manifest.Source.t;
    sourcePath : EsyBuildPackage.Config.Path.t;
    sourceType : Manifest.SourceType.t;
  }

  val pp : t Fmt.t
  val compare : t -> t -> int

  module Map : Map.S with type key = t
end

module Dependencies : sig
  type t = {
    dependencies : dependency list;
    buildTimeDependencies : dependency list;
    devDependencies : dependency list;
  }

  and dependency = (Package.t, error) result

  and error =
    | InvalidDependency of { name : string; message : string; }
    | MissingDependency of { name : string; }

  val empty : t

  val pp : t Fmt.t
  val compare : t -> t -> int
end

type t = {
  spec : EsyInstall.SandboxSpec.t;
  cfg : Config.t;
  buildConfig: EsyBuildPackage.Config.t;
  root : Package.t;
  dependencies : Dependencies.t Package.Map.t;
  scripts : Manifest.Scripts.t;
  env : Manifest.Env.t;
}

type info = (Path.t * float) list

(** Check if a directory is a sandbox *)
val isSandbox : Path.t -> bool RunAsync.t

(** Init sandbox from given the config *)
val make : cfg:Config.t -> EsyInstall.SandboxSpec.t -> (t * info) RunAsync.t

val init : t -> unit RunAsync.t
val initStore : Path.t -> unit RunAsync.t

val findPackage : (Package.t -> bool) -> t -> Package.t option

val dependencies : Package.t -> t -> Dependencies.t

module Value : module type of EsyBuildPackage.Config.Value
module Environment : module type of EsyBuildPackage.Config.Environment
module Path : module type of EsyBuildPackage.Config.Path
