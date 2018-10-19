(**
 * This module represents a solution.
 *)

(**
 * This is minimal info needed to fetch and build a package.
 *)
module Package : sig

  module Opam : sig
    type t = {
      name : Package.Opam.OpamName.t;
      version : Package.Opam.OpamPackageVersion.t;
      opam : Package.Opam.OpamFile.t;
      override : Package.OpamOverride.t option;
    }

    include S.JSONABLE with type t := t
  end

  type t = {
    name: string;
    version: Version.t;
    source: source;
    dependencies : PackageId.Set.t;
    devDependencies : PackageId.Set.t;
  }

  and source =
    | Link of {
        path : Path.t;
        manifest : ManifestSpec.t option;
        overrides: Package.Overrides.t;
      }
    | Install of {
        source : Source.t * Source.t list;
        overrides: Package.Overrides.t;
        files : Package.File.t list;
        opam : Opam.t option;
      }

  val id : t -> PackageId.t

  include S.COMPARABLE with type t := t
  include S.PRINTABLE with type t := t

  module Map : sig
    include Map.S with type key := t
  end
  module Set : Set.S with type elt := t
end

val traverse : Package.t -> PackageId.t list
val traverseWithDevDependencies : Package.t -> PackageId.t list

(**
 * This represent an isolated dependency root.
 *)
include Graph.GRAPH
  with
    type node = Package.t
    and type id = PackageId.t

(** This is an on disk format for storing solutions. *)
module LockfileV1 : sig

  val toFile :
    sandbox:Sandbox.t
    -> solution:t
    -> Fpath.t
    -> unit RunAsync.t

  val ofFile :
    sandbox:Sandbox.t
    -> Fpath.t
    -> t option RunAsync.t
end
