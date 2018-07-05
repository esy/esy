type t

type resolution = {
  name: OpamManifest.PackageName.t;
  opam: Path.t;
  url: Path.t;
  version: OpamVersion.Version.t;
}

val init : cfg:Config.t -> unit -> t RunAsync.t

val versions :
  t
  -> name : OpamManifest.PackageName.t
  -> resolution list RunAsync.t

val version :
    t
    -> name : OpamManifest.PackageName.t
    -> version : OpamVersion.Version.t
    -> OpamManifest.t option RunAsync.t
