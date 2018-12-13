(**
 * This module represents manifests and info which can be parsed out of it.
 *)

module BuildType : module type of EsyLib.BuildType
module SourceType : module type of EsyLib.SourceType

module Source : module type of EsyI.Source
module Version : module type of EsyI.Version
module Command : module type of EsyI.PackageConfig.Command
module CommandList : module type of EsyI.PackageConfig.CommandList
module ExportedEnv : module type of EsyI.PackageConfig.ExportedEnv
module Env : module type of EsyI.PackageConfig.Env

type commands =
  | OpamCommands of OpamTypes.command list
  | EsyCommands of CommandList.t
  | NoCommands

val commands_to_yojson : commands Json.encoder

type t = {
  name : string option;
  version : Version.t option;
  buildType : BuildType.t;
  build : commands;
  buildDev : CommandList.t option;
  install : commands;
  patches : (Path.t * OpamTypes.filter option) list;
  substs : Path.t list;
  exportedEnv : ExportedEnv.t;
  buildEnv : Env.t;
}

val empty : name:string option -> version:Version.t option -> unit -> t

val ofInstallationLocation :
  cfg:Config.t
  -> EsyI.Solution.Package.t
  -> EsyI.Installation.location
  -> (t option * Fpath.set) RunAsync.t

include S.PRINTABLE with type t := t
val to_yojson : t Json.encoder
