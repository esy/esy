(**
 * Representation of an opam package (opam file, url file, override).
 *)

type t = {
  name: OpamPackage.Name.t;
  version: OpamPackage.Version.t;
  path : Path.t;
  opam: OpamFile.OPAM.t;
  url: OpamFile.URL.t option;
  override : Package.OpamOverride.t;
  archive : OpamRegistryArchiveIndex.record option;
}

module File : sig
  module Cache : Memoize.MEMOIZE
    with type key := Path.t
    and type value := OpamFile.OPAM.t RunAsync.t

  val ofPath :
    ?upgradeToFormat2:bool
    -> ?cache:Cache.t
    -> Fpath.t
    -> OpamFile.OPAM.t RunAsync.t
end

val ofPath :
  name:OpamTypes.name
  -> version:OpamTypes.version
  -> Path.t
  -> t RunAsync.t
(** Load opam manifest of path. *)

val toPackage :
  name : string
  -> version : Package.Version.t
  -> t
  -> (Package.t, string) result RunAsync.t
(** Convert opam manifest to a package. *)
