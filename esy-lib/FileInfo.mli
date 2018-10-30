type t = private {
  path : Path.t;
  mtime : float option;
}

include S.COMPARABLE with type t := t

val ofPath : Path.t -> t RunAsync.t
