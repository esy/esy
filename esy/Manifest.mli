(**
 * This module represents esy/opam manifest.
 *)

module CommandList :sig
  module Command : sig
    type t =
      | Parsed of string list
      | Unparsed of string
    val pp : t Fmt.t
    val show : t -> string

    val equal : t -> t -> bool
    val compare : t -> t -> int

    val to_yojson : t Json.encoder
    val of_yojson : t Json.decoder
  end

  type t = Command.t list option
  val pp : t Fmt.t
  val show : t -> string

  val equal : t -> t -> bool
  val compare : t -> t -> int

  val to_yojson : t Json.encoder
  val of_yojson : t Json.decoder

  val empty : 'a option
end

module Scripts : sig
  type t = script StringMap.t
  and script = { command : CommandList.Command.t; }

  type scripts = t

  val equal : t -> t -> bool
  val compare : t -> t -> int

  val empty : 'a StringMap.t

  val pp : t Fmt.t
  val of_yojson : t Json.decoder
  val find : string -> t -> script option

  val ofFile : Fpath.t -> scripts RunAsync.t

  module ParseManifest : sig
    val parse : Json.t -> (scripts, string) result
  end
end

module Env : sig
  type t = item list
  and item = { name : string; value : string; }

  val pp : t Fmt.t
  val show : t -> string
  val equal : t -> t -> bool
  val compare : t -> t -> int
  val of_yojson : t Json.decoder

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

  val pp : t Fmt.t
  val show : t -> string
  val equal : t -> t -> bool
  val compare : t -> t -> int
  val empty : t
  val of_yojson : t Json.decoder
end

module BuildType : sig
  include module type of EsyBuildPackage.BuildType

  val to_yojson : t Json.encoder
  val of_yojson : t Json.decoder
end

module SourceType : sig
  include module type of EsyBuildPackage.SourceType
end

module Release : sig
  type t = {
    releasedBinaries : string list;
    deleteFromBinaryRelease : string list;
  }

  val pp : t Fmt.t
  val show : t -> string

  val of_yojson : t Json.decoder
end

module Build : sig
  type commands =
    | OpamCommands of OpamTypes.command list
    | EsyCommands of CommandList.t

  type t = {
    sourceType : SourceType.t;
    buildType : BuildType.t;
    buildCommands : commands;
    installCommands : commands;
    patches : (Path.t * OpamTypes.filter option) list;
    substs : Path.t list;
    exportedEnv : ExportedEnv.t;
    sandboxEnv : Env.t;
    buildEnv : Env.t;
  }
end

module Dependencies : sig
  type t = {
    dependencies : string list list;
    devDependencies : string list list;
    buildTimeDependencies : string list list;
    optDependencies : string list list;
  }
end

type t

val name : t -> string

val version : t -> string

val license : t -> Json.t option

val description : t -> string option

val dependencies : t -> Dependencies.t

val build : t -> Build.t option

val release : t -> Release.t option

val uniqueDistributionId : t -> string option

(**
 * Load manifest given a directory.
 *
 * Return `None` is no manifets was found.
 *
 * If manifest was found then returns also a set of paths which were used to
 * load manifest. Client code can check those paths to invalidate caches.
 *)
val ofDir : ?asRoot:bool -> Fpath.t -> (t * Fpath.set) option RunAsync.t

val dirHasManifest : Fpath.t -> bool RunAsync.t

val findEsyManifestOfDir : Fpath.t -> Fpath.t option RunAsync.t
