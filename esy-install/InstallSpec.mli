open EsyPackageConfig

type t = {
  installDev : Solution.DepSpec.t;
  installAll : Solution.DepSpec.t;
}

val compare : t -> t -> int

val eval : Solution.t -> Package.t -> t -> PackageId.Set.t
val dependencies : Solution.t -> Package.t -> t -> Package.t list
