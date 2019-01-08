(**
 * This module describes methods which are performed on build tasks through * "esy-build-package" package builder executable.
 *)

(**
 * Build task.
 *)
val build :
  ?buildOnly:bool
  -> ?quiet:bool
  -> ?logPath:Path.t
  -> EsyBuildPackage.Config.t
  -> EsyBuildPackage.Plan.t
  -> unit RunAsync.t

(*
 * Spawn an interactive shell inside tbuild environment of the task.
 *)
val buildShell :
  EsyBuildPackage.Config.t
  -> EsyBuildPackage.Plan.t
  -> Unix.process_status RunAsync.t

(*
 * Execute a command inside build environment of the task.
 *)
val buildExec :
  EsyBuildPackage.Config.t
  -> EsyBuildPackage.Plan.t
  -> Cmd.t
  -> Unix.process_status RunAsync.t
