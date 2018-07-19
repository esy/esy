(** Sandbox *)

type t = {
  cfg : Config.t;
  path : Path.t;
  resolutions : Manifest.Resolutions.t;
  root : Manifest.t;
}

val ofDir : cfg:Config.t -> Path.t -> t RunAsync.t
