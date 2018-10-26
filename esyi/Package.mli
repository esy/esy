type 'a disj = 'a list
type 'a conj = 'a list

module File : sig
  type t

  val readOfPath : prefixPath:Path.t -> filePath:Path.t -> t RunAsync.t
  val writeToDir : destinationDir:Path.t -> t -> unit RunAsync.t

  include S.COMPARABLE with type t := t
  include S.JSONABLE with type t := t
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

module Resolution : sig
  type t = {
    name : string;
    resolution : resolution;
  }

  and resolution =
    | Version of Version.t
    | SourceOverride of {source : Source.t; override : Json.t}

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

  val digest : t -> string
end

module Override : sig

  type t
  (* Package override. *)

  type build = {
    buildType : BuildType.t option;
    build : CommandList.t option;
    install : CommandList.t option;
    exportedEnv: ExportedEnv.t option;
    exportedEnvOverride: ExportedEnvOverride.t option;
    buildEnv: Env.t option;
    buildEnvOverride: EnvOverride.t option;
  }
  (* Build facet of a package override. *)

  val pp_build : build Fmt.t

  type install = {
    dependencies : NpmFormulaOverride.t option;
    devDependencies : NpmFormulaOverride.t option;
    resolutions : Resolution.resolution StringMap.t option;
  }
  (* Install facet of a package override. *)

  include S.JSONABLE with type t := t

  val ofDist : ?json:Json.t -> Dist.t -> t
  val ofJson : Json.t -> t

  val build : cfg:Config.t -> t -> build option RunAsync.t
  val install : cfg:Config.t -> t -> install option RunAsync.t
  val files : cfg:Config.t -> t -> File.t list RunAsync.t

end

(** Overrides collection. *)
module Overrides : sig
  type t

  val isEmpty : t -> bool
  (** If overrides are empty. *)

  val empty : t
  (** Empty overrides. *)

  val add : Override.t -> t -> t
  (* [add override overrides] adds single [override] on top of [overrides]. *)

  val addMany : Override.t list -> t -> t
  (* [add override_list overrides] adds many [overridea_list] overrides on top of [overrides]. *)

  val merge : t -> t -> t
  (* [merge newOverrides overrides] adds [newOverrides] on top of [overrides]. *)

  val foldWithInstallOverrides :
    cfg:Config.t
    -> f:('v -> Override.install -> 'v)
    -> init:'v
    -> t
    -> 'v RunAsync.t

  val foldWithBuildOverrides :
    cfg:Config.t
    -> f:('v -> Override.build -> 'v)
    -> init:'v
    -> t
    -> 'v RunAsync.t

  val files : cfg:Config.t -> t -> File.t list RunAsync.t

  val toList : t -> Override.t list

  include S.JSONABLE with type t := t
end


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

module Opam : sig
  module OpamFile : sig
    type t = OpamFile.OPAM.t
    val pp : t Fmt.t
    val to_yojson : t Json.encoder
    val of_yojson : t Json.decoder
  end

  module OpamName : sig
    type t = OpamPackage.Name.t
    val pp : t Fmt.t
    val to_yojson : t Json.encoder
    val of_yojson : t Json.decoder
  end

  module OpamPackageVersion : sig
    type t = OpamPackage.Version.t
    val pp : t Fmt.t
    val to_yojson : t Json.encoder
    val of_yojson : t Json.decoder
  end

  type t = {
    name : OpamName.t;
    version : OpamPackageVersion.t;
    opam : OpamFile.t;
    files : unit -> File.t list RunAsync.t;
  }
end

type t = {
  name : string;
  version : Version.t;
  originalVersion : Version.t option;
  originalName : string option;
  source : source;
  overrides : Overrides.t;
  dependencies: Dependencies.t;
  devDependencies: Dependencies.t;
  optDependencies: StringSet.t;
  resolutions : Resolutions.t;
  kind : kind;
}

and source =
  | Link of {
      path : Path.t;
      manifest : ManifestSpec.t option;
    }
  | Install of {
      source : Source.t * Source.t list;
      opam : Opam.t option;
    }

and kind =
  | Esy
  | Npm

val isOpamPackageName : string -> bool

val pp : t Fmt.t
val compare : t -> t -> int

module Map : Map.S with type key := t
module Set : Set.S with type elt := t
