val toPath :
  digest:Digestv.t
  -> Sandbox.t
  -> Solution.t
  -> Fpath.t
  -> unit RunAsync.t

val ofPath :
  ?digest:Digestv.t
  -> Sandbox.t
  -> Fpath.t
  -> Solution.t option RunAsync.t

val unsafeUpdateChecksum :
  digest:Digestv.t
  -> Fpath.t
  -> unit RunAsync.t
