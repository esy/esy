(**
 * This module represents manifests and info which can be parsed out of it.
 *)

open EsyPackageConfig

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
  buildEnv : BuildEnv.t;
}

val empty : name:string option -> version:Version.t option -> unit -> t

val ofInstallationLocation :
  cfg:Config.t
  -> EsyInstall.Package.t
  -> EsyInstall.Installation.location
  -> (t option * Fpath.set) RunAsync.t

include S.PRINTABLE with type t := t
val to_yojson : t Json.encoder
