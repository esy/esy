(**
 * This module represents a solution.
 *)

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
  end

  type t = {
    name: string;
    version: string;
    source: Source.t * Source.t list;
    files : Package.File.t list;
    opam : Opam.t option;
  }

  val pp : t Fmt.t
  val equal : t -> t -> bool

  module Map : Map.S with type key := t
  module Set : Set.S with type elt := t
end

module Id : sig
  type t

  include S.COMPARABLE with type t := t
  include S.JSONABLE with type t := t
  include S.PRINTABLE with type t := t

  val make : name:string -> source:Source.t -> unit -> t
  val ofRecord : Record.t -> t

  module Set : Set.S with type elt = t
  module Map : Map.S with type key = t
end

(**
 * This represent an isolated dependency root.
 *)
type t

val root : t -> Record.t option
val dependencies : Record.t -> t -> Record.Set.t
val records : t -> Record.Set.t

val empty : t

val addRoot : record : Record.t -> dependencies : Id.t list -> t -> t
val add : record : Record.t -> dependencies : Id.t list -> t -> t

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
