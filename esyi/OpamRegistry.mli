type t

module PackageName : sig
  type t

  val toNpm : t -> string
  val ofNpm : string -> t Run.t
  val ofNpmExn : string -> t

  val toString : t -> string
  val ofString : string -> t

  val compare : t -> t -> int
  val equal : t -> t -> bool

end

type resolution = {
  name: PackageName.t;
  version: OpamVersion.Version.t;
  opam: Path.t;
  url: Path.t option;
}

module Manifest : sig
  type t = {
    name : PackageName.t;
    version : OpamVersion.Version.t;
    opam : OpamFile.OPAM.t;
    url : OpamFile.URL.t option;
  }

  val ofFile :
    name:PackageName.t
    -> version:OpamVersion.Version.t
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
  -> name : PackageName.t
  -> resolution list RunAsync.t

val version :
    t
    -> name : PackageName.t
    -> version : OpamVersion.Version.t
    -> Manifest.t option RunAsync.t
