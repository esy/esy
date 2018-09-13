(**

  Format for _esylink file.

  Such files are used for to communicate info about sources from installer to
  builder.

 *)

type t = {

  source : Source.source;

  manifest : SandboxSpec.ManifestSpec.t option;

  override : Source.Override.t;
}

val ofFile : Path.t -> t RunAsync.t
(** Read from path. *)

val toFile : t -> Path.t -> unit RunAsync.t
(** Write at path. *)
