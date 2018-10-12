(**
 * This module represents manifests and info which can be parsed out of it.
 *)

module BuildType : module type of EsyLib.BuildType
module SourceType : module type of EsyLib.SourceType

module Source : module type of EsyInstall.Source
module Version : module type of EsyInstall.Version
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

type commands =
  | OpamCommands of OpamTypes.command list
  | EsyCommands of CommandList.t

type t = {
  buildType : BuildType.t;
  buildCommands : commands;
  installCommands : commands;
  patches : (Path.t * OpamTypes.filter option) list;
  substs : Path.t list;
  exportedEnv : ExportedEnv.t;
  buildEnv : Env.t;
}

val empty : t

val to_yojson : t Json.encoder

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
