(**
 * API for querying opam registry.
 *)

type t

type resolution = private {
  name: OpamPackage.Name.t;
  version: OpamPackage.Version.t;
  opam: Path.t;
  url: Path.t option;
}

val make : cfg:Config.t -> unit -> t
(** Configure a new opam registry instance. *)

val versions :
  name : OpamPackage.Name.t
  -> t
  -> resolution list RunAsync.t
(** Return a list of resolutions for a given opam package name. *)

val version :
  name : OpamPackage.Name.t
  -> version : OpamPackage.Version.t
  -> t
  -> OpamManifest.t option RunAsync.t
(** Return an opam manifest for a given opam package name, version. *)
