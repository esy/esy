(**

  Format for _esylink file.

  Such files are used for `link:` dependencies to signify that dependency
  sources are in a specified location.

 *)

type t = {

  (** Path to source tree. *)
  path : Path.t;

  (** Optional manifest. If no specified then manifest resolution will be
      performed. *)
  manifest : string option;
}

val ofFile : Path.t -> t RunAsync.t
(** Read from path. *)

val toFile : t -> Path.t -> unit RunAsync.t
(** Write at path. *)
