(**
 * This normalizes the info between different manifests types (opam and npm).
 *)

type t = {
  name : string;
  version : PackageInfo.Version.t;
  source : PackageInfo.Source.t;
  dependencies: PackageInfo.DependenciesInfo.t;

  (* TODO: make it non specific to opam. *)
  opam : PackageInfo.OpamInfo.t option;
}

(* TODO: get rid of that, at least publicly *)
and manifest =
  | Opam of OpamFile.manifest
  | PackageJson of PackageJson.t

val make : version:PackageInfo.Version.t -> manifest -> t Run.t
val pp : t Fmt.t
val compare : t -> t -> int

module Map : Map.S with type key := t
module Set : Set.S with type elt := t
