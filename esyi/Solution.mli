(**
 * This module represents a solution.
 *)

(**
 * This is minimal info needed to fetch and build a package.
 *)
module Record : sig
  type t = {
    name: string ;
    version: PackageInfo.Version.t ;
    source: PackageInfo.Source.t ;

    (**
    * We store OpamInfo.t as part of the lockfile as we want to lock against:
    *   1. changes in the opam->esy conversion algo
    *   2. changes in esy-opam-override
    *   3. changes in opam repository (yes, it is mutable)
    *)
    opam: PackageInfo.OpamInfo.t option;
  }

  val pp : t Fmt.t
  val equal : t -> t -> bool

  module Map : Map.S with type key := t
  module Set : Set.S with type elt := t
end

(**
 * This represent an isolated dependency root.
 *)
type t

val make : Package.t -> t list -> t

val record : t -> Record.t
val dependencies : t -> t list

val fold : f:('a -> Record.t -> 'a) -> init:'a -> t -> 'a

(**
 * Write solution to disk as a lockfile.
 *)
val toFile : cfg:Config.t -> manifest:Manifest.Root.t -> solution:t -> Fpath.t -> unit RunAsync.t

(**
 * Read solution out of a lockfile.
 *
 * This returns None either if lockfiles doesn't exist or stale.
 *
 * NOTE: We probably want to make a distinction between "does not exist" and
 * "stale".
 *)
val ofFile : cfg:Config.t -> manifest:Manifest.Root.t -> Fpath.t -> t option RunAsync.t
