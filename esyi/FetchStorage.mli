(**
 * Package storage.
 *)

type dist

(**
 * Make sure package specified by [name], [version] and [source] is in store and
 * return it.
 *)
val fetch :
  cfg : Config.t
  -> Solution.Record.t
  -> dist RunAsync.t

(**
 * Install package from storage into destination.
 *)
val install :
  cfg : Config.t
  -> path : Path.t
  -> dist
  -> unit RunAsync.t
