(**
 * Lockfile stores the solution along with metadata on disk.
 *)

(**
 * Write solution to disk as a lockfile.
 *)
val toFile : manifest:PackageJson.t -> solution:Solution.t -> Fpath.t -> unit RunAsync.t

(**
 * Read solution out of a lockfile.
 *
 * This returns None either if lockfiles doesn't exist or stale.
 *
 * NOTE: We probably want to make a distinction between "does not exist" and
 * "stale".
 *)
val ofFile : manifest:PackageJson.t -> Fpath.t -> Solution.t option RunAsync.t
