val toFile :
  sandbox:Sandbox.t
  -> solution:Solution.t
  -> Fpath.t
  -> unit RunAsync.t

val ofFile :
  sandbox:Sandbox.t
  -> Fpath.t
  -> Solution.t option RunAsync.t

