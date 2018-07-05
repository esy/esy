type t

type resolution = {
  name: OpamManifest.PackageName.t;
  version: OpamVersion.Version.t;
  opam: Path.t;
  url: Path.t;
}

module Manifest : sig
  type t = {
    name : OpamManifest.PackageName.t;
    version : OpamVersion.Version.t;
    opam : OpamFile.OPAM.t;
    url : OpamFile.URL.t option;
  }

  val ofFile :
    name:OpamManifest.PackageName.t
    -> version:OpamVersion.Version.t
    -> ?url:Fpath.t
    -> Fpath.t
    -> t RunAsync.t

  val toPackage : t -> Package.t RunAsync.t
end

val init : cfg:Config.t -> unit -> t RunAsync.t

val versions :
  t
  -> name : OpamManifest.PackageName.t
  -> resolution list RunAsync.t

val version :
    t
    -> name : OpamManifest.PackageName.t
    -> version : OpamVersion.Version.t
    -> Manifest.t option RunAsync.t
