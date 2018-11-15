(**

    Storage for package dists.

 *)

val fetchIntoCache :
  cfg : Config.t
  -> sandbox:SandboxSpec.t
  -> Dist.t
  -> Path.t RunAsync.t

val fetch :
  cfg : Config.t
  -> sandbox:SandboxSpec.t
  -> Dist.t
  -> Path.t
  -> unit RunAsync.t
