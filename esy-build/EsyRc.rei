type t = {prefixPath: option(Path.t)};

let ofPath: Fpath.t => RunAsync.t(t);
let ofPathOpt: Fpath.t => RunAsync.t(option(t));
