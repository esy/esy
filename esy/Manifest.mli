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

module EsyReleaseConfig : sig
  type t = {
    releasedBinaries : string list;
    deleteFromBinaryRelease : string list;
  }

  val pp : t Fmt.t
  val show : t -> string

  val of_yojson : t Json.decoder
end

module EsyManifest : sig
  type t = {
    build : CommandList.t;
    install : CommandList.t;
    buildsInSource : BuildType.t;
    exportedEnv : ExportedEnv.t;
    buildEnv : Env.t;
    sandboxEnv : Env.t;
    release : EsyReleaseConfig.t option;
  }

  val pp : t Fmt.t
  val show : t -> string

  val of_yojson : t Json.decoder

  val empty : t
end

module Esy : sig

  module Dependencies : sig
    type t = string StringMap.t
    val empty : t
    val pp : t Fmt.t
    val of_yojson : t Json.decoder
  end

  type t = {
    name : string;
    version : string;
    description : string option;
    license : Json.t option;
    dependencies : Dependencies.t;
    peerDependencies : Dependencies.t;
    devDependencies : Dependencies.t;
    optDependencies : Dependencies.t;
    buildTimeDependencies : Dependencies.t;
    esy : EsyManifest.t option;
    _resolved : string option;
  }

  val pp : t Fmt.t
  val show : t -> string
  val of_yojson : t Json.decoder

  val name : t -> string
  val version : t -> string
  val dependencies : t -> string list list
  val devDependencies : t -> string list list
  val optDependencies : t -> string list list
  val buildTimeDependencies : t -> string list list

  val ofFile : Fpath.t -> t RunAsync.t
  val findOfDir : Fpath.t -> Fpath.t option RunAsync.t
  val ofDir : Fpath.t -> (t * Fpath.set) option RunAsync.t
end

module Opam : sig
  type t

  type commands =
    | Commands of OpamTypes.command list
    | OverridenCommands of CommandList.t

  val opamName : t -> string

  val name : t -> string
  val version : t -> string

  val sourceType : t -> SourceType.t
  val buildType : t -> BuildType.t

  val buildCommands : t -> commands
  val installCommands : t -> commands
  val exportedEnv : t -> ExportedEnv.t

  val dependencies : t -> string list list
  val optDependencies : t -> string list list

  val patches : t -> (OpamTypes.basename * OpamTypes.filter option) list
  val substs : t -> OpamTypes.basename list
end

type t =
  | Esy of Esy.t
  | Opam of Opam.t

type commands =
  | OpamCommands of OpamTypes.command list
  | EsyCommands of CommandList.t

val name : t -> string
val version : t -> string

val dependencies : t -> string list list
val devDependencies : t -> string list list
val optDependencies : t -> string list list
val buildTimeDependencies : t -> string list list

val sourceType : t -> SourceType.t
val buildType : t -> BuildType.t option
val buildCommands : t -> commands
val installCommands : t -> commands

val exportedEnv : t -> ExportedEnv.t
val sandboxEnv : t -> Env.t
val buildEnv : t -> Env.t

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
