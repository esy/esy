open EsyInstall.PackageConfig

type 'a disj = 'a list
type 'a conj = 'a list

module Dep : sig
  type t = {
    name : string;
    req : req;
  }

  and req =
    | Npm of EsyInstall.SemverVersion.Constraint.t
    | NpmDistTag of string
    | Opam of EsyInstall.OpamPackageVersion.Constraint.t
    | Source of EsyInstall.SourceSpec.t

  val pp : t Fmt.t
end

module Dependencies : sig
  type t =
    | OpamFormula of Dep.t disj conj
    | NpmFormula of NpmFormula.t

  include S.PRINTABLE with type t := t
  include S.COMPARABLE with type t := t

  val toApproximateRequests : t -> EsyInstall.Req.t list

  val filterDependenciesByName : name:string -> t -> t
end

type t = {
  name : string;
  version : EsyInstall.Version.t;
  originalVersion : EsyInstall.Version.t option;
  originalName : string option;
  source : EsyInstall.PackageSource.t;
  overrides : EsyInstall.Overrides.t;
  dependencies: Dependencies.t;
  devDependencies: Dependencies.t;
  peerDependencies: NpmFormula.t;
  optDependencies: StringSet.t;
  resolutions : EsyInstall.PackageConfig.Resolutions.t;
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
