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
  config : Config.t
  -> Solution.pkg
  -> pkg RunAsync.t

(**
 * Install package from storage into destination.
 *)
val install :
  config : Config.t
  -> dst : Path.t
  -> pkg
  -> unit RunAsync.t
