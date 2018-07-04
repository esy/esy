(**
 * Fetch & install solution for the currently configured sandbox.
 *)
val fetch :
  cfg:Config.t
  -> Solution.t
  -> unit RunAsync.t

(**
 * Check if the solution is installed.
 *)
val isInstalled : cfg:Config.t -> Solution.t -> bool RunAsync.t
