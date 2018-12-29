type t = {
  prefixPath : Path.t option;
}

val ofPath : Fpath.t -> t RunAsync.t
