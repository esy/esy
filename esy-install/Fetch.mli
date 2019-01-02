(**

  Fetch & install sandbox solution.

 *)

open EsyPackageConfig

val fetch :
  InstallSpec.t
  -> Sandbox.t
  -> Solution.t
  -> unit RunAsync.t
(**
 * Fetch & install solution for the currently configured sandbox using pnp.js
 * installation strategy.
 *)

val isInstalled :
  InstallSpec.t
  -> Sandbox.t
  -> Solution.t
  -> bool RunAsync.t
(** Check if the solution is installed. *)

val fetchOverrideFiles :
  Config.t
  -> SandboxSpec.t
  -> Override.t
  -> File.t list RunAsync.t
