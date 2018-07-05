(**
 * This module represents a solution.
 *)

(**
 * This is minimal info needed to fetch and build a package.
 *)
module Record : sig
  type t = {
    name: string;
    version: Package.Version.t;
    source: Package.Source.t;

    (**
    * We store OpamInfo.t as part of the lockfile as we want to lock against:
    *   1. changes in the opam->esy conversion algo
    *   2. changes in esy-opam-override
    *   3. changes in opam repository (yes, it is mutable)
    *)
    opam: Package.OpamInfo.t option;
  }

  val pp : t Fmt.t
  val equal : t -> t -> bool

  val ofPackage : Package.t -> t

  module Map : Map.S with type key := t
  module Set : Set.S with type elt := t
end

(**
 * This represent an isolated dependency root.
 *)
type t = root

and root = {
  record: Record.t;
  dependencies: root StringMap.t;
}

val make : Record.t -> t list -> t

val record : t -> Record.t
val dependencies : t -> t list

val findDependency : name:string -> t -> t option

val fold : f:('a -> Record.t -> 'a) -> init:'a -> t -> 'a
val equal : t -> t -> bool
val pp : Format.formatter -> t -> unit
val to_yojson : t -> Json.t

(** This is an on disk format for storing solutions. *)
module LockfileV1 : sig

  val toFile :
    cfg:Config.t
    -> manifest:Manifest.Root.t
    -> solution:t
    -> Fpath.t
    -> unit RunAsync.t

  val ofFile :
    cfg:Config.t
    -> manifest:Manifest.Root.t
    -> Fpath.t
    -> t option RunAsync.t
end
