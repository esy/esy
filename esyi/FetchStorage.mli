(**
 * Package storage.
 *)

(** Distribution. *)
module Dist : sig
  type t
  val id : t -> PackageId.t
  val pkg : t -> Solution.Package.t
  val source : t -> Source.t
  val sourceInstallPath : t -> Path.t
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

val install :
  Dist.t
  -> unit RunAsync.t
(**
 * Unpack fetched dist from storage into source cache and return path.
 *)
