open EsyPackageConfig

type t = {
  solveRoot : DepSpec.t;
  solveLink : DepSpec.t;
  solveAll : DepSpec.t;
}

include S.JSONABLE with type t := t

val eval : t -> InstallManifest.t -> InstallManifest.t -> InstallManifest.Dependencies.t Run.t
val compare : t -> t -> int
