val toPath :
  checksum:string
  -> sandbox:Sandbox.t
  -> solution:Solution.t
  -> Fpath.t
  -> unit RunAsync.t

val ofPath :
  checksum:string
  -> sandbox:Sandbox.t
  -> Fpath.t
  -> Solution.t option RunAsync.t

val unsafeUpdateChecksum :
  checksum:string
  -> Fpath.t
  -> unit RunAsync.t
