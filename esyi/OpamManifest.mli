(**
 * Utilities for working with opam manifests.
 *)

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

type t = {
  name: PackageName.t ;
  version: OpamVersion.Version.t ;
  fileName: string ;
  build: string list list ;
  install: string list list ;
  patches: string list ;
  files: (Path.t * string) list ;
  dependencies: PackageInfo.Dependencies.t ;
  buildDependencies: PackageInfo.Dependencies.t ;
  devDependencies: PackageInfo.Dependencies.t ;
  peerDependencies: PackageInfo.Dependencies.t ;
  optDependencies: PackageInfo.Dependencies.t ;
  available: [ `IsNotAvailable  | `Ok ] ;
  source: PackageInfo.Source.t ;
  exportedEnv: PackageJson.ExportedEnv.t
}

val parse :
  name:PackageName.t
  -> version:OpamVersion.Version.t
  -> OpamParserTypes.opamfile
  -> t

module Url : sig
  val parse : OpamParserTypes.opamfile -> PackageInfo.SourceSpec.t
end

val toPackageJson :
  t
  -> PackageInfo.Version.t
  -> PackageInfo.OpamInfo.t
