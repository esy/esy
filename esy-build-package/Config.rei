type t =
  pri {
    projectPath: Fpath.t,
    globalStorePrefix: Fpath.t,
    storePath: Fpath.t,
    localStorePath: Fpath.t,
    disableSandbox: bool,
    globalPathVariable: option(string),
  };

let pp: Fmt.t(t);
let show: t => string;
let to_yojson: EsyLib.Json.encoder(t);

type storePathConfig =
  | StorePath(Fpath.t)
  | StorePathOfPrefix(Fpath.t)
  | StorePathDefault;

let storePrefixDefault: Fpath.t;
let configureStorePath: (storePathConfig, Fpath.t) => Run.t(Fpath.t, _);

let make:
  (
    ~globalStorePrefix: Fpath.t,
    ~disableSandbox: bool,
    ~storePath: storePathConfig,
    ~projectPath: Fpath.t,
    ~localStorePath: Fpath.t,
    ~globalPathVariable: option(string),
    unit
  ) =>
  Run.t(t, _);

type config = t;

/* Config parametrized string value */
module Value: {
  include EsyLib.Abstract.STRING with type ctx = config;
  let store: t;
  let globalStorePrefix: t;
  let localStore: t;
  let project: t;
};

module Path: {
  include EsyLib.Abstract.PATH with type ctx = config;
  let toValue: t => Value.t;
  let globalStorePrefix: t;
  let store: t;
  let localStore: t;
  let project: t;
};

module Environment:
  EsyLib.Environment.S with type value = Value.t and type ctx = t;
