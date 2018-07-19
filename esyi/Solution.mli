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
      version : Package.Opam.OpamVersion.t;
      opam : Package.Opam.OpamFile.t;
      override : Package.OpamOverride.t option;
    }
  end

  type t = {
    name: string;
    version: Package.Version.t;
    source: Package.Source.t * Package.Source.t list;
    files : Package.File.t list;
    opam : Opam.t option;
  }

  val pp : t Fmt.t
  val equal : t -> t -> bool

  module Map : Map.S with type key := t
  module Set : Set.S with type elt := t
end

module Id : sig
  type t = string * Package.Version.t

  module Map : Map.S with type key := t
  module Set : Set.S with type elt := t
end

(**
 * This represent an isolated dependency root.
 *)
type t

val root : t -> Record.t option
val dependencies : Record.t -> t -> Record.Set.t
val records : t -> Record.Set.t

val equal : t -> t -> bool

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
