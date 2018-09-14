module Command : sig
  type t =
    | Parsed of string list
    | Unparsed of string

  include S.COMPARABLE with type t := t
  include S.JSONABLE with type t := t
  include S.PRINTABLE with type t := t
end

module CommandList : sig

  type t = Command.t list

  include S.COMPARABLE with type t := t
  include S.JSONABLE with type t := t
  include S.PRINTABLE with type t := t

  val empty : t
end

module ExportedEnv : sig
  type t = item list

  and item = {
    name : string;
    value : string;
    scope : scope;
    exclusive : bool;
  }

  and scope = Local | Global

  val empty : t
  
  include S.COMPARABLE with type t := t
  include S.JSONABLE with type t := t
  include S.PRINTABLE with type t := t

end

module Dependencies : sig
  type t = Req.t list
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
