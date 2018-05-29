(**
 * Package storage.
 *)

(**
 * Package inside the storage
 *
 * The only way to get one is via [fetch].
 *)
type pkg

(**
 * Make sure package specified by [name], [version] and [source] is in store and
 * return it.
 *)
val fetch :
  config : Shared.Config.t
  -> name : string
  -> version : Shared.Lockfile.realVersion
  -> source : Shared.Solution.Source.t
  -> pkg RunAsync.t

(**
 * Install package from storage into destination.
 *)
val install :
  config : Shared.Config.t
  -> dst : Path.t
  -> pkg
  -> unit RunAsync.t
