(**
 * Project representation.
 *)

type t = {
  path : Path.t;
  sandbox : sandbox;
  sandboxByName : sandbox StringMap.t;
}

and sandbox =
  | Esy of {path : Path.t; name : string option}
  | Opam of {path : Path.t}
  | AggregatedOpam of {paths : Path.t list}

val ofDir : Path.t -> t option RunAsync.t
(** Read project repr of a directory path. Returns None if no project is found. *)

val initByName :
  init:(Path.t -> sandbox -> 'sandbox RunAsync.t)
  -> ?name:string
  -> t
  -> 'sandbox RunAsync.t
(** Init project from a description. *)
