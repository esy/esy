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
    source: source;
    overrides: Package.Overrides.t;
    dependencies : PackageId.Set.t;
    devDependencies : PackageId.Set.t;
  }

  and source =
    | Link of Source.link
    | Install of {
        source : Dist.t * Dist.t list;
        opam : OpamResolution.t option;
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

val traverse : Package.t -> PackageId.t list
val traverseWithDevDependencies : Package.t -> PackageId.t list
