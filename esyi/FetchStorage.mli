(**
 * Package storage.
 *)

val fetchSource :
  cfg : Config.t
  -> Source.t
  -> Path.t RunAsync.t
(** Fetch source and cache a compressed tarball. *)

(** Distribution. *)
module Dist : sig
  type t
  val pp : Format.formatter -> t -> unit
end

val fetch :
  cfg : Config.t
  -> Solution.Record.t
  -> Dist.t RunAsync.t
(**
 * Make sure package specified by [name], [version] and [source] is in store and
 * return it.
 *)

val install :
  cfg : Config.t
  -> path : Path.t
  -> Dist.t
  -> unit RunAsync.t
(**
 * Install package from storage into destination.
 *)
