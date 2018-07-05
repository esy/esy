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
  dependencies: Package.Dependencies.t ;
  buildDependencies: Package.Dependencies.t ;
  devDependencies: Package.Dependencies.t ;
  peerDependencies: Package.Dependencies.t ;
  optDependencies: Package.Dependencies.t ;
  available: [ `IsNotAvailable  | `Ok ] ;
  source: Package.Source.t ;
  exportedEnv: Package.ExportedEnv.t
}

type 'v parser

val parseManifest :
  name:PackageName.t
  -> version:OpamVersion.Version.t
  -> t parser

val parseUrl : Package.SourceSpec.t parser

(** Run parser and log all errors, warnings *)
val runParsePath : parser:'v parser -> Path.t -> 'v RunAsync.t

val toPackageJson :
  t
  -> Package.Version.t
  -> Package.OpamInfo.t

val toPackage : ?name:string -> ?version:Package.Version.t -> t -> Package.t Run.t
