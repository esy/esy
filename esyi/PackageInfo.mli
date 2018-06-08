(**
 * This represent the concrete and stable location from which we can download
 * some package.
 *)
module Source : sig
  type t =
      Archive of string * string
    | Git of string * string
    | Github of string * string * string
    | LocalPath of Fpath.t
    | NoSource

  val compare : t -> t -> int
  val toString : t -> string
  val parse : string -> (t, string) result
  val to_yojson : t -> [> `String of string ]
  val of_yojson : Json.t -> (t, string) result
end

(**
 * A concrete version.
 *)
module Version : sig
  type t =
      Npm of NpmVersion.Version.t
    | Opam of DebianVersion.t
    | Source of Source.t

  val compare : t -> t -> int
  val toString : t -> string
  val parse : string -> (t, string) result
  val to_yojson : t -> [> `String of string ]
  val of_yojson : Json.t -> (t, string) result
  val toNpmVersion : t -> string
end

(**
 * This is a spec for a source, which at some point will be resolved to a
 * concrete source Source.t.
 *)
module SourceSpec : sig
  type t =
      Archive of string * string option
    | Git of string * string option
    | Github of string * string * string option
    | LocalPath of Fpath.t
    | NoSource
  val toString : t -> string
  val to_yojson : t -> [> `String of string ]
end

(**
 * This representes a concrete version which at some point will be resolved to a
 * concrete version Version.t.
 *)
module VersionSpec : sig
  type t =
      Npm of NpmVersion.Formula.t
    | Opam of OpamVersion.Formula.t
    | Source of SourceSpec.t
  val toString : t -> string
  val to_yojson : t -> [> `String of string ]

  val satisfies : version:Version.t -> t -> bool
end

module Req : sig
  type t

  val toString : t -> string
  val to_yojson : t -> [> `String of string ]

  val make : name:string -> spec:string -> t
  val ofSpec : name:string -> spec:VersionSpec.t -> t

  val name : t -> string
  val spec : t -> VersionSpec.t
end

module Dependencies : sig
  type t = Req.t list
  val empty : 'a list
  val of_yojson : Json.t -> (Req.t list, string) result
  val to_yojson : t -> [> `Assoc of (string * [> `String of string ]) list ]
  val merge : Req.t list -> Req.t list -> Req.t list
end

module DependenciesInfo : sig
  type t = {
    dependencies : Dependencies.t;
    buildDependencies : Dependencies.t;
    devDependencies : Dependencies.t;
  }
  val to_yojson : t -> Json.t
  val of_yojson : Json.t -> t Ppx_deriving_yojson_runtime.error_or
end

module OpamInfo : sig
  type t = Json.t * (Fpath.t * string) list * string list
  val to_yojson : t -> Json.t
  val of_yojson : Json.t -> t Ppx_deriving_yojson_runtime.error_or
end
