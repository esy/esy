(**

  Esy specific opam information which is needed for building packages installed
  from opam.

 *)

type t = {
  source : Source.t;
  override : Package.OpamOverride.t option;
}

val ofFile : Path.t -> t RunAsync.t
val toFile : t -> Path.t -> unit RunAsync.t
