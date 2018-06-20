(**
 * This module represents a solution.
 *)

type t

type pkg = {
  name: string ;
  version: PackageInfo.Version.t ;
  source: PackageInfo.Source.t ;

  (**
   * We store OpamInfo.t as part of the lockfile as we want to lock against:
   *   1. changes in the algo opam->esy conversion
   *   2. changes in esy-opam-override
   *   3. changes in opam repository (yes, it is mutable)
   *)
  opam: PackageInfo.OpamInfo.t option;
}

val make : root:Package.t -> dependencies:Package.Set.t -> t

(**
 * List all packages in a solution.
 *)
val packages : t -> pkg list

(**
 * Write solution to disk as a lockfile.
 *)
val toFile : cfg:Config.t -> manifest:PackageJson.t -> solution:t -> Fpath.t -> unit RunAsync.t

(**
 * Read solution out of a lockfile.
 *
 * This returns None either if lockfiles doesn't exist or stale.
 *
 * NOTE: We probably want to make a distinction between "does not exist" and
 * "stale".
 *)
val ofFile : cfg:Config.t -> manifest:PackageJson.t -> Fpath.t -> t option RunAsync.t
