type t

type pkg = {
  name: OpamFile.PackageName.t;
  opam: Path.t;
  url: Path.t;
  version: OpamVersion.Version.t;
}

val init : cfg:Config.t -> unit -> t RunAsync.t

val versions :
  t
  -> name : OpamFile.PackageName.t
  -> (OpamVersion.Version.t * pkg) list RunAsync.t

val version :
    t
    -> name : OpamFile.PackageName.t
    -> version : OpamVersion.Version.t
    -> OpamFile.manifest option RunAsync.t
