type req = string;

/**

  Resolve [req] using node module resolution algorithm against [basedir].

  If no [basedir] is provided then current executable's dirname is used.

  */
let resolve: (~basedir: Fpath.t=?, req) => result(Fpath.t, [> Rresult.R.msg]);

/* TODO: do not expose it here. */
let realpath: Fpath.t => result(Fpath.t, [> Rresult.R.msg]);
