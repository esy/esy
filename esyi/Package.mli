type 'a disj = 'a list
type 'a conj = 'a list

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
 *
 * TODO: remove it
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

(**
 * TODO: remove it
 *)
module Req : sig
  type t = private {name : string; spec : VersionSpec.t}

  val pp : Format.formatter -> t -> unit

  val toString : t -> string
  val to_yojson : t -> [> `String of string ]

  val make : name:string -> spec:string -> t
  val ofSpec : name:string -> spec:VersionSpec.t -> t

  val name : t -> string
  val spec : t -> VersionSpec.t
end

(** A single dependency constraint. *)
module Dep : sig
  type t = {
    name : string;
    req : req;
  }

  and req =
    | Npm of SemverVersion.Formula.Constraint.t
    | Opam of OpamVersion.Formula.Constraint.t
    | Source of SourceSpec.t

  val pp : t Fmt.t
  val matches : name : string -> version : Version.t -> t -> bool
end

(** A formula for a dependency. *)
module DepFormula : sig
  type t =
    | Npm of SemverVersion.Formula.CNF.t
    | Opam of OpamVersion.Formula.CNF.t
    | Source of SourceSpec.t

  val matches : version : Version.t -> t -> bool
  val pp : t Fmt.t
end

(** A formula which mentions multiple dependencies. *)
module Dependencies : sig
  type t = Dep.t disj conj

  val empty : t

  val override : dep:Dep.t -> t -> t
  val overrideMany : deps:Dep.t list -> t -> t

  val mapDeps : f:(Dep.t -> 'a) -> t -> 'a disj conj
  val filterDeps : f:(Dep.t -> bool) -> t -> t

  val subformulaForPackage : name:string -> t -> t option

  (**
   * Produce a list of pkgname, approx depformula for each pkg mentioned in a
   * depformula.
   *
   * Note that the dep formulas are approximate and should not be used for dep
   * solving directly but rathe to prune unrelated versions.
   *)
  val describeByPackageName : t -> (string * DepFormula.t) list

  val pp : t Fmt.t
  val show : t -> string
end

module Resolutions : sig
  type t

  val empty : t
  val find : t -> string -> Version.t option
  val apply : t -> Dep.t -> Dep.t option

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

module File : sig
  type t = {
    name : Path.t;
    content : string
  }

  val to_yojson : t Json.encoder
  val of_yojson : t Json.decoder
end

module OpamInfo : sig
  type t = {
    manifest : Json.t;
    files : unit -> File.t list RunAsync.t;
  }
  val show : t -> string
end

type t = {
  name : string;
  version : Version.t;
  source : source;
  dependencies: Dependencies.t;
  devDependencies: Dependencies.t;

  (* TODO: make it non specific to opam. *)
  opam : OpamInfo.t option;
  kind : kind;
}

and source =
  | Source of Source.t
  | SourceSpec of SourceSpec.t

and kind =
  | Esy
  | Npm

val pp : t Fmt.t
val compare : t -> t -> int

module Map : Map.S with type key := t
module Set : Set.S with type elt := t
