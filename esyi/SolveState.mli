module Cache : sig

  module Packages : Memoize.MEMOIZE with
    type key := (string * PackageInfo.Version.t)
    and type value := Package.t RunAsync.t

  module NpmPackages : Memoize.MEMOIZE with
    type key := string
    and type value := (NpmVersion.Version.t * PackageJson.t) list RunAsync.t

  module OpamPackages : Memoize.MEMOIZE with
    type key := string
    and type value := (OpamVersion.Version.t * OpamFile.ThinManifest.t) list RunAsync.t

  type t = {
    opamRegistry: OpamRegistry.t;
    npmPackages: (string, Yojson.Safe.json) Hashtbl.t;
    opamPackages: (string, OpamFile.manifest) Hashtbl.t;

    pkgs: Packages.t;
    availableNpmVersions: NpmPackages.t;
    availableOpamVersions: OpamPackages.t;
  }

  val make : cfg:Config.t -> unit -> t RunAsync.t
end

module Universe : sig
  type t
  val add : pkg:Package.t -> t -> t
  val mem : pkg:Package.t -> t -> bool
  val toCudfUniverse : t -> Cudf.universe
end

type t = {
  cfg: Config.t;
  cache: Cache.t;
  mutable universe: Universe.t;
}

val make :
  ?cache : Cache.t
  -> cfg:Config.t
  -> unit
  -> t RunAsync.t

val addPackage :
  state:t
  -> Package.t
  -> unit

val runSolver :
  ?strategy:string
  -> univ:Universe.t
  -> Package.t
  -> Package.t list option
