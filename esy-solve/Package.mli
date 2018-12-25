open EsyPackageConfig

type 'a disj = 'a list
type 'a conj = 'a list

module Dep : sig
  type t = {
    name : string;
    req : req;
  }

  and req =
    | Npm of SemverVersion.Constraint.t
    | NpmDistTag of string
    | Opam of OpamPackageVersion.Constraint.t
    | Source of SourceSpec.t

  val pp : t Fmt.t
end

module Dependencies : sig
  type t =
    | OpamFormula of Dep.t disj conj
    | NpmFormula of NpmFormula.t

  include S.PRINTABLE with type t := t
  include S.COMPARABLE with type t := t

  val toApproximateRequests : t -> Req.t list

  val filterDependenciesByName : name:string -> t -> t
end

type t = {
  name : string;
  version : Version.t;
  originalVersion : Version.t option;
  originalName : string option;
  source : PackageSource.t;
  overrides : Overrides.t;
  dependencies: Dependencies.t;
  devDependencies: Dependencies.t;
  peerDependencies: NpmFormula.t;
  optDependencies: StringSet.t;
  resolutions : Resolutions.t;
  kind : kind;
}

and kind =
  | Esy
  | Npm

val isOpamPackageName : string -> bool

val pp : t Fmt.t
val compare : t -> t -> int

val to_yojson : t Json.encoder

module Map : Map.S with type key := t
module Set : Set.S with type elt := t
