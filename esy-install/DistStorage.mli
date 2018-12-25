open EsyPackageConfig

(**

    Storage for package dists.

 *)

val fetchIntoCache :
  cfg : Config.t
  -> sandbox:SandboxSpec.t
  -> Dist.t
  -> Path.t RunAsync.t

type fetchedDist

val ofCachedTarball : Path.t -> fetchedDist
val ofDir : Path.t -> fetchedDist

val fetch :
  cfg : Config.t
  -> sandbox:SandboxSpec.t
  -> Dist.t
  -> fetchedDist RunAsync.t

val unpack :
  fetchedDist
  -> Path.t
  -> unit RunAsync.t

val cache :
  fetchedDist
  -> Path.t
  -> fetchedDist RunAsync.t
