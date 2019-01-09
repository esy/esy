type t =
  pri {
    path: Path.t,
    mtime: option(float),
  };

include S.COMPARABLE with type t := t;

let ofPath: Path.t => RunAsync.t(t);
let ofPathSet: Fpath.set => RunAsync.t(list(t));
