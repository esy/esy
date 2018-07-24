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

type config = t

/* Config parametrized string value */
module Value: {
  type t;

  let store : t;
  let localStore : t;
  let sandbox : t;

  let show : t => string;
  let pp : Fmt.t(t);
  let equal : t => t => bool;

  let ofString: string => t;
  let toString : (~cfg: config, t) => Run.t(string, _);

  let of_yojson: EsyLib.Json.decoder(t);
  let to_yojson: EsyLib.Json.encoder(t);
};
