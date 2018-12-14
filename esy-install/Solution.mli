(**
 * This module represents a solution.
 *)

include Graph.GRAPH
  with
    type node = Package.t
    and type id = PackageId.t

val findByPath : DistPath.t -> t -> Package.t option
val findByName : string -> t -> Package.t option
val findByNameVersion : string -> Version.t -> t -> Package.t option

val traverse : Package.t -> PackageId.t list
val traverseWithDevDependencies : Package.t -> PackageId.t list
