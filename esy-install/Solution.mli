(**
 * This module represents a solution.
 *)

module Override : sig
  type t =
    | OfJson of {json : Json.t;}
    | OfDist of {dist : Dist.t; json : Json.t;}
    | OfOpamOverride of {
        path : Path.t;
        json : Json.t;
      }

  type build = {
    buildType : BuildType.t option;
    build : PackageConfig.CommandList.t option;
    install : PackageConfig.CommandList.t option;
    exportedEnv: PackageConfig.ExportedEnv.t option;
    exportedEnvOverride: PackageConfig.ExportedEnvOverride.t option;
    buildEnv: PackageConfig.Env.t option;
    buildEnvOverride: PackageConfig.EnvOverride.t option;
  }

  type install = {
    dependencies : PackageConfig.NpmFormulaOverride.t option;
    devDependencies : PackageConfig.NpmFormulaOverride.t option;
    resolutions : PackageConfig.Resolution.resolution StringMap.t option [@default None];
  }

  val ofJson : Json.t -> t
  val ofDist : Json.t -> Dist.t -> t

  val files : Config.t -> SandboxSpec.t -> t -> File.t list RunAsync.t
end

module Overrides : sig
  type t = Override.t list

  val empty : t
  val isEmpty : t -> bool

  val add : Override.t -> t -> t
  (* [add override overrides] adds single [override] on top of [overrides]. *)

  val addMany : Override.t list -> t -> t
  (* [add override_list overrides] adds many [overridea_list] overrides on top of [overrides]. *)

  val merge : t -> t -> t
  (* [merge newOverrides overrides] adds [newOverrides] on top of [overrides]. *)

  val files :
    Config.t
    -> SandboxSpec.t
    -> t
    -> File.t list RunAsync.t

  val foldWithBuildOverrides :
    f:('v -> Override.build -> 'v)
    -> init:'v
    -> t
    -> 'v RunAsync.t

  val foldWithInstallOverrides :
    f:('v -> Override.install -> 'v)
    -> init:'v
    -> t
    -> 'v RunAsync.t

end

(**
 * This is minimal info needed to fetch and build a package.
 *)
module Package : sig

  type t = {
    id: PackageId.t;
    name: string;
    version: Version.t;
    source: PackageSource.t;
    overrides: Overrides.t;
    dependencies : PackageId.Set.t;
    devDependencies : PackageId.Set.t;
  }

  include S.COMPARABLE with type t := t
  include S.PRINTABLE with type t := t

  module Map : Map.S with type key := t
  module Set : Set.S with type elt := t
end

include Graph.GRAPH
  with
    type node = Package.t
    and type id = PackageId.t

val findByPath : DistPath.t -> t -> Package.t option
val findByName : string -> t -> Package.t option
val findByNameVersion : string -> Version.t -> t -> Package.t option

val traverse : Package.t -> PackageId.t list
val traverseWithDevDependencies : Package.t -> PackageId.t list
