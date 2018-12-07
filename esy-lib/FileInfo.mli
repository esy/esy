type t = private {
  path : Path.t;
  mtime : float option;
}

include S.COMPARABLE with type t := t

val ofPath : Path.t -> t RunAsync.t
val ofPathSet : Fpath.set -> t list RunAsync.t
