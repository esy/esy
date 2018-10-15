(**
 * Package storage.
 *)

(** Distribution. *)
module Dist : sig
  type t
  val id : t -> PackageId.t
  val source : t -> Source.t
  val pp : Format.formatter -> t -> unit
end

val fetch :
  sandbox : Sandbox.t
  -> Solution.Package.t
  -> Dist.t RunAsync.t
(**
 * Make sure package specified by [name], [version] and [source] is in store and
 * return it.
 *)

type status =
  | Cached
  | Fresh

val install :
  sandbox : Sandbox.t
  -> Dist.t
  -> (status * Path.t) RunAsync.t
(**
 * Unpack fetched dist from storage into source cache and return path.
 *)

val installNodeModules :
  sandbox : Sandbox.t
  -> path : Path.t
  -> Dist.t
  -> unit RunAsync.t
(**
 * Install fetched dist from storage into destination.
 *)
