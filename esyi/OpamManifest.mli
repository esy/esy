(**
 * Representation of an opam package (opam file, url file, override).
 *)

type t = {
  name: OpamPackage.Name.t;
  version: OpamPackage.Version.t;
  opam: OpamFile.OPAM.t;
  url: OpamFile.URL.t option;
  override : EsyInstall.Solution.Override.t option;
  opamRepositoryPath : Path.t option;
}

module File : sig
  module Cache : Memoize.MEMOIZE
    with type key := Path.t
    and type value := OpamFile.OPAM.t RunAsync.t

  val ofPath :
    ?upgradeIfOpamVersionIsLessThan:OpamVersion.t
    -> ?cache:Cache.t
    -> Fpath.t
    -> OpamFile.OPAM.t RunAsync.t
end

val ofString :
  name:OpamTypes.name
  -> version:OpamTypes.version
  -> string
  -> t Run.t

val ofPath :
  name:OpamTypes.name
  -> version:OpamTypes.version
  -> Path.t
  -> t RunAsync.t
(** Load opam manifest of path. *)

val toPackage :
  ?source:EsyInstall.Source.t
  -> name : string
  -> version : EsyInstall.Version.t
  -> t
  -> (Package.t, string) result RunAsync.t
(** Convert opam manifest to a package. *)
