type t = {
  root : Package.t;
  scripts : Manifest.Scripts.t;
  manifestInfo : (Path.t * float) list;
}

val ofDir : Config.t -> t RunAsync.t
