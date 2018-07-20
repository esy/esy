type t = {
  sandboxPath: Fpath.t,
  storePath: Fpath.t,
  localStorePath: Fpath.t,
  rsyncCmd: string,
  fastreplacestringCmd: string,
};

let make : (
  ~prefixPath: option(Fpath.t),
  ~sandboxPath: option(Fpath.t),
  ~rsyncCmd: string=?,
  ~fastreplacestringCmd: string=?,
  unit
) => Run.t(t, _);

let renderString : (~cfg: t, string) => Run.t(string, _);
