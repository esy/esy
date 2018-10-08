(**

  Fetch & install sandbox solution.

 *)

val fetchNodeModules :
  sandbox:Sandbox.t
  -> Solution.t
  -> unit RunAsync.t
(** Fetch & install solution for the currently configured sandbox. *)

val fetch :
  sandbox:Sandbox.t
  -> Solution.t
  -> unit RunAsync.t
(**
 * Fetch & install solution for the currently configured sandbox using pnp.js
 * installation strategy.
 *)

val isInstalled :
  sandbox:Sandbox.t
  -> Solution.t
  -> bool RunAsync.t
(** Check if the solution is installed. *)
