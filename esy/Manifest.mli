(**
 * This module represents manifests and info which can be parsed out of it.
 *)

module BuildType : module type of EsyLib.BuildType
module SourceType : module type of EsyLib.SourceType

module Source : module type of EsyInstall.Source
module Command : module type of EsyInstall.Package.Command
module CommandList : module type of EsyInstall.Package.CommandList
module ExportedEnv : module type of EsyInstall.Package.ExportedEnv
module Env : module type of EsyInstall.Package.Env

module Scripts : sig
  type t = script StringMap.t
  and script = { command : Command.t; }
  val empty : t
  val find : string -> t -> script option
end

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
    name : string;
    version : string;
    buildType : BuildType.t;
    buildCommands : commands;
    installCommands : commands;
    patches : (Path.t * OpamTypes.filter option) list;
    substs : Path.t list;
    exportedEnv : ExportedEnv.t;
    buildEnv : Env.t;
  }

  val empty : string -> string -> t
  val to_yojson : t Json.encoder
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
  val empty : t
  val show : t -> string
end

module type MANIFEST = sig
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
   * Extract release config from manifest
   *
   * Not all packages have release config defined so we return `None` in this
   * case.
   *)
  val scripts : t -> Scripts.t Run.t

  val sandboxEnv : t -> Env.t Run.t
  (** Extract sandbox environment from manifest. *)
end

include MANIFEST

(**
 * Load manifest given a directory.
 *
 * Return `None` is no manifets was found.
 *
 * If manifest was found then returns also a set of paths which were used to
 * load manifest. Client code can check those paths to invalidate caches.
 *)
val ofDir :
  ?manifest:EsyInstall.ManifestSpec.Filename.t
  -> Path.t
  -> (t * Path.Set.t) option RunAsync.t

val ofSandboxSpec :
  cfg:Config.t
  -> EsyInstall.SandboxSpec.t
  -> (t * EsyInstall.Package.Overrides.t * Path.Set.t) RunAsync.t

val dirHasManifest : Fpath.t -> bool RunAsync.t
