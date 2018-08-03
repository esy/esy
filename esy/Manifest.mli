(**
 * This module represents manifests and info which can be parsed out of it.
 *)

module CommandList :sig
  module Command : sig
    type t =
      | Parsed of string list
      | Unparsed of string
  end

  type t = Command.t list option
  val empty : t
  val show : t -> string
end

module Scripts : sig
  type t = script StringMap.t
  and script = { command : CommandList.Command.t; }
  val empty : t
  val find : string -> t -> script option
  val ofFile : Fpath.t -> t RunAsync.t
end

module Env : sig
  type t = item list
  and item = { name : string; value : string; }
  val empty : t
  val show : t -> string
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

  val show : t -> string
  val empty : t
end

module BuildType : module type of EsyBuildPackage.BuildType
module SourceType : module type of EsyBuildPackage.SourceType

(**
 * Release configuration.
 *)
module Release : sig
  type t = {
    releasedBinaries : string list;
    deleteFromBinaryRelease : string list;
  }
end

(**
 * Build configuration.
 *)
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

(**
 * Dependencies info.
 *)
module Dependencies : sig
  type t = {
    dependencies : string list list;
    devDependencies : string list list;
    buildTimeDependencies : string list list;
    optDependencies : string list list;
  }
end

(**
 * Manifest.
 *
 * This can be either esy manifest (package.json/esy.json) or opam manifest but
 * this type abstracts them out.
 *)
type t

(** Name. *)
val name : t -> string

(** Version. *)
val version : t -> string

(** License. *)
val license : t -> Json.t option

(** Description. *)
val description : t -> string option

(**
 * Extract dependency info.
 *)
val dependencies : t -> Dependencies.t

(**
 * Extract build config from manifest
 *
 * Not all packages have build config defined so we return `None` in this case.
 *)
val build : t -> Build.t option

(**
 * Extract release config from manifest
 *
 * Not all packages have release config defined so we return `None` in this
 * case.
 *)
val release : t -> Release.t option

(**
 * Unique id of the release.
 *
 * This could be a released version, git sha commit or some checksum of package
 * contents if any.
 *
 * This info is used to construct a build key for the corresponding package.
 *)
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
