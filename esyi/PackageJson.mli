module Scripts : sig
  type t = script StringMap.t
  and script = { command : Metadata.Command.t; }
  val empty : t
  val find : string -> t -> script option

  val of_yojson : t Json.decoder
end

module Env : sig
  include module type of Metadata.Env

  val empty : t
  val show : t -> string

  include S.JSONABLE with type t := t
end

module ExportedEnv : sig
  include module type of Metadata.ExportedEnv

  val empty : t

  include S.COMPARABLE with type t := t
  include S.JSONABLE with type t := t
  include S.PRINTABLE with type t := t

end

module Dependencies : sig
  include module type of Metadata.Dependencies

  val empty : t

  val override : t -> t -> t
  val find : name:string -> t -> Req.t option

  val pp : t Fmt.t

  include S.COMPARABLE with type t := t
  include S.JSONABLE with type t := t
end

module EsyPackageJson : sig
  type t = {
    _dependenciesForNewEsyInstaller : Dependencies.t option;
  }
  val of_yojson : t Json.decoder
end

module Resolutions : sig
  include module type of Metadata.Resolutions

  val empty : t
  val find : t -> string -> Version.t option

  val entries : t -> (string * Version.t) list

  include S.JSONABLE with type t := t
end

type t = {
  name : string option;
  version : SemverVersion.Version.t option;
  dependencies : Dependencies.t;
  devDependencies : Dependencies.t;
  esy : EsyPackageJson.t option;
}

val of_yojson : t Json.decoder

val findInDir : Path.t -> Path.t option RunAsync.t
(** Find package.json (or esy.json) in a directory *)

val ofFile : Path.t -> t RunAsync.t
(** Read package.json (or esy.json) from a file *)

val ofDir : Path.t -> t RunAsync.t
(** Read package.json (or esy.json) from a directory *)
