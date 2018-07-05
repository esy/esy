(**
 * This represent the concrete and stable location from which we can download
 * some package.
 *)
module Source : sig
  type t =
      Archive of string * string
    | Git of {remote : string; commit : string}
    | Github of {user : string; repo : string; commit : string}
    | LocalPath of Path.t
    | LocalPathLink of Path.t
    | NoSource

  val compare : t -> t -> int
  val toString : t -> string
  val parse : string -> (t, string) result
  val to_yojson : t -> [> `String of string ]
  val of_yojson : Json.t -> (t, string) result

  val pp : t Fmt.t
  val equal : t -> t -> bool
end

(**
 * A concrete version.
 *)
module Version : sig
  type t =
      Npm of SemverVersion.Version.t
    | Opam of OpamVersion.Version.t
    | Source of Source.t

  val compare : t -> t -> int
  val toString : t -> string
  val parse : string -> (t, string) result
  val parseExn : string -> t
  val to_yojson : t -> [> `String of string ]
  val of_yojson : Json.t -> (t, string) result
  val toNpmVersion : t -> string

  val pp : Format.formatter -> t -> unit
  val equal : t -> t -> bool

  module Map : Map.S with type key := t
end

(**
 * This is a spec for a source, which at some point will be resolved to a
 * concrete source Source.t.
 *)
module SourceSpec : sig
  type t =
      Archive of string * string option
    | Git of {remote : string; ref : string option}
    | Github of {user : string; repo : string; ref : string option}
    | LocalPath of Path.t
    | LocalPathLink of Path.t
    | NoSource
  val toString : t -> string
  val to_yojson : t -> [> `String of string ]
  val pp : t Fmt.t
end

(**
 * This representes a concrete version which at some point will be resolved to a
 * concrete version Version.t.
 *)
module VersionSpec : sig
  type t =
      Npm of SemverVersion.Formula.DNF.t
    | Opam of OpamVersion.Formula.DNF.t
    | Source of SourceSpec.t
  val toString : t -> string
  val to_yojson : t -> [> `String of string ]

  val matches : version:Version.t -> t -> bool
  val ofVersion : Version.t -> t
end

module Req : sig
  type t

  val pp : Format.formatter -> t -> unit

  val toString : t -> string
  val to_yojson : t -> [> `String of string ]

  val make : name:string -> spec:string -> t
  val ofSpec : name:string -> spec:VersionSpec.t -> t

  val name : t -> string
  val spec : t -> VersionSpec.t
end

(**
 * A collection of dependency requests.
 *
 * There maybe possible multiple requests of the same name.
 * TODO: Make sure there's no requests of the same name possible and provide
 *       explicit API for conjuction/override.
 *)
module Dependencies : sig
  type t

  val empty : t

  val add : req:Req.t -> t -> t
  val addMany : reqs:Req.t list -> t -> t

  val override : req:Req.t -> t -> t
  val overrideMany : reqs:Req.t list -> t -> t

  val map : f:(Req.t -> Req.t) -> t -> t

  val findByName : name:string -> t -> Req.t option

  val toList : t -> Req.t list
  val ofList : Req.t list -> t

  val pp : t Fmt.t

  val of_yojson : Json.t -> (t, string) result
  val to_yojson : t -> Json.t
end

module Resolutions : sig
  type t

  val empty : t
  val find : t -> string -> Version.t option
  val apply : t -> Req.t -> Req.t option

  val entries : t -> (string * Version.t) list

  val to_yojson : t Json.encoder
  val of_yojson : t Json.decoder
end

module ExportedEnv : sig
  type t = item list
  and item = { name : string; value : string; scope : scope; }
  and scope = [ `Global | `Local ]

  val empty : t
  val of_yojson : t Json.decoder
  val to_yojson : t Json.encoder
end

module OpamInfo : sig
  type t = {
    packageJson : Json.t;
    files : (Path.t * string) list;
    patches : string list;
  }
  val to_yojson : t -> Json.t
  val of_yojson : Json.t -> t Ppx_deriving_yojson_runtime.error_or
  val show : t -> string
end

type t = {
  name : string;
  version : Version.t;
  source : Source.t;
  dependencies: Dependencies.t;
  devDependencies: Dependencies.t;

  (* TODO: make it non specific to opam. *)
  opam : OpamInfo.t option;
  kind : kind;
}

and kind =
  | Esy
  | Npm

val pp : t Fmt.t
val compare : t -> t -> int

module Map : Map.S with type key := t
module Set : Set.S with type elt := t
