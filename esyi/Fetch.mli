(**
 * Fetch & install solution for the currently configured sandbox.
 *)
val fetch :
  sandbox:Sandbox.t
  -> Solution.t
  -> unit RunAsync.t

(**
 * Check if the solution is installed.
 *)
val isInstalled : sandbox:Sandbox.t -> Solution.t -> bool RunAsync.t
