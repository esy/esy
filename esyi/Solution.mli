(**
 * This module represents a solution.
 *)

module Id : sig
  type t

  include S.COMPARABLE with type t := t
  include S.PRINTABLE with type t := t
  include S.JSONABLE with type t := t

  val make : string -> Version.t -> t
  val name : t -> string
  val version : t -> Version.t

  module Set : Set.S with type elt = t
  module Map : sig
    include Map.S with type key = t
    val to_yojson : 'a Json.encoder -> 'a t Json.encoder
    val of_yojson : 'a Json.decoder -> 'a t Json.decoder
  end
end

(**
 * This is minimal info needed to fetch and build a package.
 *)
module Record : sig

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
    source: Source.t * Source.t list;
    overrides: Package.Overrides.t;
    files : Package.File.t list;
    opam : Opam.t option;
  }

  val id : t -> Id.t

  include S.COMPARABLE with type t := t
  include S.PRINTABLE with type t := t

  module Map : sig
    include Map.S with type key := t
  end
  module Set : Set.S with type elt := t
end

(**
 * This represent an isolated dependency root.
 *)
include Graph.GRAPH
  with
    type node = Record.t
    and type id = Id.t

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
