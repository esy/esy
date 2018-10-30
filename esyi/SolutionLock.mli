val toPath :
  sandbox:Sandbox.t
  -> solution:Solution.t
  -> Fpath.t
  -> unit RunAsync.t

val ofPath :
  sandbox:Sandbox.t
  -> Fpath.t
  -> Solution.t option RunAsync.t

