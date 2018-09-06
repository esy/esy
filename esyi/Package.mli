type 'a disj = 'a list
type 'a conj = 'a list

module Source : module type of Source
module Version : module type of Version
module SourceSpec : module type of SourceSpec
module VersionSpec : module type of VersionSpec

module Req : sig
  type t = private {name : string; spec : VersionSpec.t}

  val pp : Format.formatter -> t -> unit

  val toString : t -> string
  val to_yojson : t Json.encoder

  val parse : string -> (t, string) result

  val make : name:string -> spec:VersionSpec.t -> t

  val matches : name:string -> version:Version.t -> t -> bool
end

(** A single dependency constraint. *)
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
  val matches : name : string -> version : Version.t -> t -> bool
end

module Resolutions : sig
  type t

  val empty : t
  val find : t -> string -> Version.t option

  val entries : t -> (string * Version.t) list

  val to_yojson : t Json.encoder
  val of_yojson : t Json.decoder
end

module Dependencies : sig
  type t =
    | OpamFormula of Dep.t disj conj
    | NpmFormula of Req.t conj

  val pp : t Fmt.t
  val show : t -> string

  val toApproximateRequests : t -> Req.t list
  val applyResolutions : Resolutions.t -> t -> t
end

module ExportedEnv : sig
  type t = item list
  and item = { name : string; value : string; scope : scope; }
  and scope = [ `Global | `Local ]

  val empty : t
  val of_yojson : t Json.decoder
  val to_yojson : t Json.encoder
end

module NpmDependencies : sig
  type t = Req.t conj
  val empty : t
  val pp : t Fmt.t
  val of_yojson : t Json.decoder
  val to_yojson : t Json.encoder
  val toOpamFormula : t -> Dep.t disj conj
  val override : t -> t -> t
  val find : name:string -> t -> Req.t option
end

module File : sig
  type t = {
    name : Path.t;
    content : string;
    perm : int;
  }

  val equal : t -> t -> bool
  val to_yojson : t Json.encoder
  val of_yojson : t Json.decoder
end

module OpamOverride : sig
  module Opam : sig
    type t = {
      source: source option;
      files: File.t list;
    }

    and source = {
      url: string;
      checksum: string;
    }

    val empty : t
  end

  module Command : sig
    type t =
      | Args of string list
      | Line of string
  end

  type t = {
    build : Command.t list option;
    install : Command.t list option;
    dependencies : NpmDependencies.t;
    peerDependencies : NpmDependencies.t;
    exportedEnv : ExportedEnv.t;
    opam : Opam.t;
  }
  val to_yojson : t -> Json.t
  val of_yojson : Json.t -> t Ppx_deriving_yojson_runtime.error_or
  val equal : t -> t -> bool
  val pp : Format.formatter -> t -> unit
  val show : t -> string
  val empty : t
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
    override : OpamOverride.t;
  }
  val show : t -> string
end

type t = {
  name : string;
  version : Version.t;
  originalVersion : Version.t option;
  source : source * source list;
  dependencies: Dependencies.t;
  devDependencies: Dependencies.t;
  opam : Opam.t option;
  kind : kind;
}

and source =
  | Source of Source.t
  | SourceSpec of SourceSpec.t

and kind =
  | Esy
  | Npm

val isOpamPackageName : string -> bool
val pp : t Fmt.t
val compare : t -> t -> int

module Map : Map.S with type key := t
module Set : Set.S with type elt := t
