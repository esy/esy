(**
 * This normalizes the info between different manifests types (opam and npm).
 *)

type t = {
  name : string;
  version : PackageInfo.Version.t;
  source : PackageInfo.Source.t;
  dependencies: PackageInfo.Dependencies.t;
  buildDependencies: PackageInfo.Dependencies.t;
  devDependencies: PackageInfo.Dependencies.t;

  (* TODO: make it non specific to opam. *)
  opam : PackageInfo.OpamInfo.t option;
}

(**
 * Make package out of opam manifest.
 *
 * Optional arguments `name` and `version` are used to override name and version
 * specified in manifest if needed.
 *)
val ofOpam :
  ?name:string
  -> ?version:PackageInfo.Version.t
  -> OpamFile.manifest
  -> t Run.t

(**
 * Make package out of package.json manifest.
 *
 * Optional arguments `name` and `version` are used to override name and version
 * specified in manifest if needed.
 *)
val ofPackageJson :
  ?name:string
  -> ?version:PackageInfo.Version.t
  -> PackageJson.t
  -> t Run.t

val pp : t Fmt.t
val compare : t -> t -> int

module Map : Map.S with type key := t
module Set : Set.S with type elt := t
