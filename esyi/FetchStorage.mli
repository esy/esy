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
  val sourceStagePath : t -> Path.t
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

type installation

val install :
  onBeforeLifecycle:(Path.t -> unit RunAsync.t)
  -> Dist.t
  -> installation RunAsync.t
(** Unpack fetched dist from storage into source cache and return path. *)

val linkBins :
  Path.t
  -> installation
  -> unit RunAsync.t
(** Link executables declared in ["bin"] field of package.json. *)
