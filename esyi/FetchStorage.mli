(**
 * Package storage.
 *)

module Dist : sig
  type t
  val pp : Format.formatter -> t -> unit
end

(**
 * Make sure package specified by [name], [version] and [source] is in store and
 * return it.
 *)
val fetch :
  cfg : Config.t
  -> Solution.Record.t
  -> Dist.t RunAsync.t

(**
 * Install package from storage into destination.
 *)
val install :
  cfg : Config.t
  -> path : Path.t
  -> Dist.t
  -> unit RunAsync.t
