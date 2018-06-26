(**
 * Fetch & install solution for the currently configured sandbox.
 *)
val fetch : 
  cfg:Config.t
  -> Solution.t
  -> unit RunAsync.t

(**
 * Check if the physical installation layout is up to date.
 *)
val check : cfg:Config.t -> Solution.t -> bool RunAsync.t
