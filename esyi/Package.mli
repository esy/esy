type 'a disj = 'a list
type 'a conj = 'a list

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

module Override : sig
  type t = {
    build : PackageJson.CommandList.t option;
    install : PackageJson.CommandList.t option;
  }
end

module Resolution : sig
  type t = {
    name : string;
    resolution : resolution;
  }

  and resolution =
    | Version of Version.t
    | SourceOverride of {source : Source.t; override : Override.t}

  include S.COMPARABLE with type t := t
  include S.PRINTABLE with type t := t
end

module Resolutions : sig
  type t

  val empty : t
  val find : t -> string -> Resolution.t option

  val entries : t -> Resolution.t list

  val to_yojson : t Json.encoder
  val of_yojson : t Json.decoder

  val digest : t -> string
end

module Dependencies : sig
  type t =
    | OpamFormula of Dep.t disj conj
    | NpmFormula of Req.t conj

  val pp : t Fmt.t
  val show : t -> string

  val toApproximateRequests : t -> Req.t list
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

  type t = {
    build : PackageJson.CommandList.t option;
    install : PackageJson.CommandList.t option;
    dependencies : PackageJson.Dependencies.t;
    peerDependencies : PackageJson.Dependencies.t;
    exportedEnv : PackageJson.ExportedEnv.t;
    opam : Opam.t;
  }

  val empty : t

  include S.JSONABLE with type t := t
  include S.COMPARABLE with type t := t
  include S.PRINTABLE with type t := t
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

and kind =
  | Esy
  | Npm

val isOpamPackageName : string -> bool
val pp : t Fmt.t
val compare : t -> t -> int

val ofPackageJson :
  name:string
  -> version:Version.t
  -> source:source
  -> PackageJson.t
  -> t
(** Convert package.json into a package *)

module Map : Map.S with type key := t
module Set : Set.S with type elt := t
