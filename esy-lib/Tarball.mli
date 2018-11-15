(**
 * Operate on tarballs on filesystem
 *
 * The implementaton uses tar command.
 *)

(**
 * Unpack [filename] into [dst].
 *)
val unpack :
  ?stripComponents:int
  -> dst:Path.t
  -> Path.t
  -> unit RunAsync.t

(**
 * Create tarball [filename] by archiving [src] path.
 *)
val create :
  filename:Path.t
  -> ?outpath:string
  -> Path.t
  -> unit RunAsync.t

val checkIfZip : Path.t -> bool Lwt.t
