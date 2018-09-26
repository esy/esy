(**

    Storage for package sources.

 *)

type source
(** Fetched source. *)

val fetch :
  cfg : Config.t
  -> Source.t
  -> (source, Run.error) result RunAsync.t
(** Fetch source. *)

val unpack :
  cfg : Config.t
  -> dst : Path.t
  -> source
  -> unit RunAsync.t
(** Unpack fetched source in a specified directory. *)

val fetchAndUnpack :
  cfg : Config.t
  -> dst : Path.t
  -> Source.t
  -> unit RunAsync.t
(** Shortcut for fetch & unpack *)
