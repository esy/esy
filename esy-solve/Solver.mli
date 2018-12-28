(**
 * Package dependency solver.
 *)

(**
 * Solve dependencies for the root
 *)
val solve : SolveSpec.t -> Sandbox.t -> EsyInstall.Solution.t RunAsync.t
