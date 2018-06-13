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

module VersionMap : sig

  type t

  val make : ?size:int -> unit -> t
  val update : t -> string -> PackageInfo.Version.t -> int -> unit
  val findVersion : name:string -> cudfVersion:int -> t -> PackageInfo.Version.t option
  val findVersionExn : name:string -> cudfVersion:int -> t -> PackageInfo.Version.t

  val findCudfVersion : name:string -> version:PackageInfo.Version.t -> t -> int option
  val findCudfVersionExn : name:string -> version:PackageInfo.Version.t -> t -> int

end

type t = {
  cfg: Config.t;
  cache: Cache.t;
  versionMap: VersionMap.t;
  universe: Cudf.universe;
}

val make :
  ?cache : Cache.t
  -> cfg:Config.t
  -> unit
  -> t RunAsync.t

val addPackage :
  state:t
  -> cudfVersion:int
  -> dependencies:PackageInfo.Dependencies.t
  -> Package.t
  -> unit

(** TODO: refactor it away *)
val cudfDep :
  from : Package.t
  -> state : t
  -> PackageInfo.Req.t
  -> (string * ([> `Eq ] * int) option) list

