(**
 * API for querying opam registry.
 *)

type t

val make : cfg:Config.t -> unit -> t
(** Configure a new opam registry instance. *)

val versions :
  ?ocamlVersion : OpamPackageVersion.Version.t
  -> name : OpamPackage.Name.t
  -> t
  -> OpamResolution.t list RunAsync.t
(** Return a list of resolutions for a given opam package name. *)

val version :
  name : OpamPackage.Name.t
  -> version : OpamPackage.Version.t
  -> t
  -> OpamManifest.t option RunAsync.t
(** Return an opam manifest for a given opam package name, version. *)
