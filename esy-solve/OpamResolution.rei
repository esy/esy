/** This represents a ref to a package from opam repository. */;

open EsyPackageConfig;

type t = PackageSource.opam;

let make: (OpamPackage.Name.t, OpamPackage.Version.t, Path.t) => t;

let name: t => string;
let version: t => Version.t;
let path: t => Path.t;

let files: t => RunAsync.t(list(File.t));
let opam: t => RunAsync.t(OpamFile.OPAM.t);
let digest: t => RunAsync.t(Digestv.t);

include S.JSONABLE with type t := t;
