module Store = EsyLib.Store;

type t = {
  fastreplacestringPath: Fpath.t,
  sandboxPath: Fpath.t,
  storePath: Fpath.t,
  localStorePath: Fpath.t,
};

type config = t;

let cwd = EsyLib.Path.v(Sys.getcwd());

/**
 * Initialize config optionally with prefixPath and sandboxPath.
 *
 * If prefixPath is not provided then ~/.esy is used.
 * If sandboxPath is not provided then $PWD us used.
 */
let make = (~fastreplacestringPath=?, ~prefixPath=?, ~sandboxPath=?, ()) =>
  Run.(
    {
      let%bind prefixPath =
        switch (prefixPath) {
        | Some(v) => Ok(v)
        | None =>
          let home = EsyLib.Path.homePath();
          Ok(home / ".esy");
        };
      let%bind sandboxPath =
        switch (sandboxPath) {
        | Some(v) => Ok(v)
        | None => Bos.OS.Dir.current()
        };
      let fastreplacestringPath =
        switch (fastreplacestringPath) {
        | Some(p) => p
        | None => Fpath.v("fastreplacestring.exe")
        };
      let%bind padding = Store.getPadding(prefixPath);
      let storePath = prefixPath / (Store.version ++ padding);
      let localStorePath =
        sandboxPath / "node_modules" / ".cache" / "_esy" / "store";
      Ok({fastreplacestringPath, storePath, sandboxPath, localStorePath});
    }
  );

let render = (cfg, v) => {
  let path = v =>
    v |> EsyLib.Path.toString |> EsyLib.Path.normalizePathSlashes;
  let sandboxPath = path(cfg.sandboxPath);
  let storePath = path(cfg.storePath);
  let localStorePath = path(cfg.localStorePath);
  let lookupVar =
    fun
    | "sandbox" => Some(sandboxPath)
    | "store" => Some(storePath)
    | "localStore" => Some(localStorePath)
    | _ => None;
  PathSyntax.renderExn(lookupVar, v);
};

module Value = {
  include EsyLib.Abstract.String.Make({
    type ctx = config;
    let render = render;
  });

  let sandbox = v("%{sandbox}%");
  let store = v("%{store}%");
  let localStore = v("%{localStore}%");
};

module Path: {
  include EsyLib.Abstract.PATH with type ctx = config;
  let toValue: t => Value.t;
  let store: t;
  let localStore: t;
  let sandbox: t;
} = {
  include EsyLib.Path;
  type ctx = config;

  let sandbox = v("%{sandbox}%");
  let store = v("%{store}%");
  let localStore = v("%{localStore}%");

  let toValue = path =>
    path |> toString |> EsyLib.Path.normalizePathSlashes |> Value.v;

  let toPath = (cfg, path) => path |> toString |> render(cfg) |> v;

  let ofPath = (cfg, p) => {
    let p =
      if (isAbs(p)) {
        p;
      } else {
        cwd /\/ p;
      };
    let p = normalize(p);
    if (equal(p, cfg.storePath)) {
      store;
    } else if (equal(p, cfg.localStorePath)) {
      localStore;
    } else if (equal(p, cfg.sandboxPath)) {
      sandbox;
    } else {
      switch (remPrefix(cfg.storePath, p)) {
      | Some(suffix) => store /\/ suffix
      | None =>
        switch (remPrefix(cfg.localStorePath, p)) {
        | Some(suffix) => localStore /\/ suffix
        | None =>
          switch (remPrefix(cfg.sandboxPath, p)) {
          | Some(suffix) => sandbox /\/ suffix
          | None => p
          }
        }
      };
    };
  };
};

module Environment = EsyLib.Environment.Make(Value);
