(**
 * This module represents a solution.
 *)

module File : module type of Package.File

(**
 * This is minimal info needed to fetch and build a package.
 *)
module Package : sig

  type t = {
    name: string;
    version: Version.t;
    source: Package.source;
    overrides: Package.Overrides.t;
    dependencies : PackageId.Set.t;
    devDependencies : PackageId.Set.t;
  }

  type opam = {
    opamname : OpamPackage.Name.t;
    opamversion : OpamPackage.Version.t;
    opamfile : OpamFile.OPAM.t;
  }

  val id : t -> PackageId.t

  val readOpam : t -> opam option RunAsync.t
  val readOpamFiles : t -> File.t list RunAsync.t

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
