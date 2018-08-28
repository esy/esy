(**
 * Project representation.
 *)

type 'sandbox project = {
  path : Path.t;
  sandbox : 'sandbox;
  sandboxByName : 'sandbox StringMap.t;
}

type t = sandbox project

and sandbox =
  | Esy of {path : Path.t; name : string option}
  | Opam of {path : Path.t}
  | AggregatedOpam of {paths : Path.t list}

val ofDir : Path.t -> t option RunAsync.t
(** Read project repr of a directory path. Returns None if no project is found. *)

val initWith :
  (sandbox -> 'sandbox RunAsync.t)
  -> t
  -> 'sandbox project RunAsync.t
(** Init project from a description. *)

val forEach :
  (string option -> 'sandbox -> unit RunAsync.t)
  -> 'sandbox project
  -> unit RunAsync.t
