(**

  Format for _esylink file.

  Such files are used for `link:` dependencies to signify that dependency
  sources are in a specified location.

 *)

type t = {
  (** Source. *)
  source : Source.t;

  (** Optional override. *)
  override : Package.Override.t list;

  (** opam metadata in case this is an installation from opam repository *)
  opam : Solution.Record.Opam.t option;
}

val ofDirIfExists : Path.t -> t option RunAsync.t
(** Read from path. *)

val ofDir : Path.t -> t RunAsync.t
(** Read from path. *)

val toDir : t -> Path.t -> unit RunAsync.t
(** Write at path. *)
