type t

type resolution = {
  name: OpamPackage.Name.t;
  version: OpamPackage.Version.t;
  opam: Path.t;
  url: Path.t option;
}

module Manifest : sig
  type t

  val ofFile :
    name:OpamTypes.name
    -> version:OpamTypes.version
    -> Path.t
    -> t RunAsync.t

  val toPackage :
    name : string
    -> version : Package.Version.t
    -> t
    -> Package.t RunAsync.t
end

val make : cfg:Config.t -> unit -> t

val versions :
  ?ocamlVersion:OpamVersion.Version.t
  -> name : OpamPackage.Name.t
  -> t
  -> resolution list RunAsync.t

val version :
    name : OpamPackage.Name.t
    -> version : OpamPackage.Version.t
    -> t
    -> Manifest.t option RunAsync.t
