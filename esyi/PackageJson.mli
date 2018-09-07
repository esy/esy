module EsyPackageJson : sig
  type t = {
    _dependenciesForNewEsyInstaller : Package.NpmDependencies.t option;
  }
  val of_yojson : t Json.decoder
end

type t = {
  name : string option;
  version : SemverVersion.Version.t option;
  dependencies : Package.NpmDependencies.t;
  devDependencies : Package.NpmDependencies.t;
  esy : EsyPackageJson.t option;
}

val of_yojson : t Json.decoder

val findInDir : Path.t -> Path.t option RunAsync.t
(** Find package.json (or esy.json) in a directory *)

val ofFile : Path.t -> t RunAsync.t
(** Read package.json (or esy.json) from a file *)

val ofDir : Path.t -> t RunAsync.t
(** Read package.json (or esy.json) from a directory *)

val toPackage :
  name:string
  -> version:Version.t
  -> source:Package.source
  -> t
  -> Package.t
(** Convert package.json into a package *)
