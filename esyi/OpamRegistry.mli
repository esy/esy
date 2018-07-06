type t

type resolution = {
  name: OpamPackage.Name.t;
  version: OpamPackage.Version.t;
  opam: Path.t;
  url: Path.t option;
}

module Manifest : sig
  type t = {
    name : OpamPackage.Name.t;
    version : OpamPackage.Version.t;
    opam : OpamFile.OPAM.t;
    url : OpamFile.URL.t option;
  }

  val ofFile :
    name:OpamPackage.Name.t
    -> version:OpamPackage.Version.t
    -> ?url:Fpath.t
    -> Fpath.t
    -> t RunAsync.t

  val toPackage :
    name : string
    -> version : Package.Version.t
    -> t
    -> Package.t RunAsync.t
end

val init : cfg:Config.t -> unit -> t RunAsync.t

val versions :
  t
  -> name : OpamPackage.Name.t
  -> resolution list RunAsync.t

val version :
    t
    -> name : OpamPackage.Name.t
    -> version : OpamPackage.Version.t
    -> Manifest.t option RunAsync.t
