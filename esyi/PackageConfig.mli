module Resolution : sig
  type t = {
    name : string;
    resolution : resolution;
  }

  and resolution =
    | Version of Version.t
    | SourceOverride of {source : Source.t; override : Json.t}

  val resolution_of_yojson : resolution Json.decoder
  val resolution_to_yojson : resolution Json.encoder

  include S.COMPARABLE with type t := t
  include S.PRINTABLE with type t := t
end

module Resolutions : sig
  type t

  val empty : t
  val add : string -> Resolution.resolution -> t -> t
  val find : t -> string -> Resolution.t option

  val entries : t -> Resolution.t list

  val to_yojson : t Json.encoder
  val of_yojson : t Json.decoder

  val digest : t -> Digestv.t
end

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

module Env : sig
  type t = item StringMap.t

  and item = {
    name : string;
    value : string;
  }

  val empty : t

  include S.COMPARABLE with type t := t
  include S.JSONABLE with type t := t
  include S.PRINTABLE with type t := t
end

module EnvOverride : sig
  type t = Env.item StringMap.Override.t

  include S.COMPARABLE with type t := t
  include S.PRINTABLE with type t := t
  include S.JSONABLE with type t := t
end

module ExportedEnv : sig
  type t = item StringMap.t

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

module ExportedEnvOverride : sig
  type t = ExportedEnv.item StringMap.Override.t

  include S.COMPARABLE with type t := t
  include S.PRINTABLE with type t := t
  include S.JSONABLE with type t := t
end

module NpmFormula : sig
  type t = Req.t list
  val empty : t

  val override : t -> t -> t
  val find : name:string -> t -> Req.t option

  val pp : t Fmt.t

  include S.COMPARABLE with type t := t
  include S.JSONABLE with type t := t
end

module NpmFormulaOverride : sig
  type t = Req.t StringMap.Override.t

  include S.COMPARABLE with type t := t
  include S.PRINTABLE with type t := t
  include S.JSONABLE with type t := t
end

