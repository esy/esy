(**

    Storage for package sources.

 *)

type archive
(** Fetched source. *)

val fetch :
  cfg : Config.t
  -> Dist.t
  -> archive Run.t RunAsync.t
(** Fetch source. *)

val unpack :
  cfg : Config.t
  -> dst : Path.t
  -> archive
  -> unit RunAsync.t
(** Unpack fetched source in a specified directory. *)

val fetchAndUnpack :
  cfg : Config.t
  -> dst : Path.t
  -> Dist.t
  -> unit RunAsync.t
(** Shortcut for fetch & unpack *)

val fetchAndUnpackToCache :
  cfg:Config.t
  -> Dist.t
  -> Fpath.t RunAsync.t
