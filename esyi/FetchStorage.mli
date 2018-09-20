(**
 * Package storage.
 *)

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
