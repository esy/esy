(**
 * This module represents a solution.
 *)

(**
 * This is minimal info needed to fetch and build a package.
 *)
module Package : sig

  type t = {
    id: PackageId.t;
    name: string;
    version: Version.t;
    source: Package.source;
    overrides: Package.Overrides.t;
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
