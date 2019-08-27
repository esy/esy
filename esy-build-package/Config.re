module Store = EsyLib.Store;

[@deriving (show, to_yojson)]
type t = {
  projectPath: EsyLib.Path.t,
  globalStorePrefix: EsyLib.Path.t,
  storePath: EsyLib.Path.t,
  localStorePath: EsyLib.Path.t,
  disableSandbox: bool,
};

type config = t;

type storePathConfig =
  | StorePath(Fpath.t)
  | StorePathOfPrefix(Fpath.t)
  | StorePathDefault;

let storePrefixDefault = EsyLib.Path.(homePath() / ".esy");
let cwd = EsyLib.Path.v(Sys.getcwd());

let initStore = (path: Fpath.t) => {
  open Run;
  let%bind () = mkdir(Fpath.(path / "i"));
  let%bind () = mkdir(Fpath.(path / "b"));
  let%bind () = mkdir(Fpath.(path / "s"));
  return();
};

let rec configureStorePath = (cfg, globalStorePrefix) => {
  open Run;
  let%bind path =
    switch (cfg) {
    | StorePath(storePath) => return(storePath)
    | StorePathOfPrefix(prefixPath) =>
      let%bind padding = Store.getPadding(prefixPath);
      let storePath = prefixPath / (Store.version ++ padding);
      return(storePath);
    | StorePathDefault =>
      configureStorePath(
        StorePathOfPrefix(storePrefixDefault),
        globalStorePrefix,
      )
    };
  let%bind () = initStore(path);
  let%bind () = mkdir(Fpath.(globalStorePrefix / Store.version / "b"));
  return(path);
};

let make =
    (
      ~globalStorePrefix,
      ~storePath,
      ~projectPath,
      ~localStorePath,
      ~disableSandbox,
      (),
    ) => {
  open Run;
  let%bind storePath = configureStorePath(storePath, globalStorePrefix);
  let%bind () =
    switch (EsyLib.System.Platform.host) {
    | Windows => return()
    | _ =>
      let shortcutPath = EsyLib.Path.(parent(storePath) / Store.version);

      if%bind (exists(shortcutPath)) {
        return();
      } else {
        symlink(
          ~target=storePath,
          EsyLib.Path.(parent(storePath) / Store.version),
        );
      };
    };
  let%bind () = initStore(localStorePath);
  return({
    projectPath,
    globalStorePrefix,
    storePath,
    localStorePath,
    disableSandbox,
  });
};

let render = (cfg, v) => {
  let path = v =>
    v |> EsyLib.Path.show |> EsyLib.Path.normalizePathSepOfFilename;
  let projectPath = path(cfg.projectPath);
  let storePath = path(cfg.storePath);
  let globalStorePrefix = path(cfg.globalStorePrefix);
  let localStorePath = path(cfg.localStorePath);
  let lookupVar =
    fun
    | "globalStorePrefix" => Some(globalStorePrefix)
    | "project" => Some(projectPath)
    | "store" => Some(storePath)
    | "localStore" => Some(localStorePath)
    | _ => None;
  EsyLib.PathSyntax.renderExn(lookupVar, v);
};

module Value = {
  include EsyLib.Abstract.String.Make({
    type ctx = config;
    let render = render;
  });

  let globalStorePrefix = v("%{globalStorePrefix}%");
  let project = v("%{project}%");
  let store = v("%{store}%");
  let localStore = v("%{localStore}%");
};

module Path: {
  include EsyLib.Abstract.PATH with type ctx = config;
  let toValue: t => Value.t;
  let globalStorePrefix: t;
  let store: t;
  let localStore: t;
  let project: t;
} = {
  include EsyLib.Path;
  type ctx = config;

  let globalStorePrefix = v("%{globalStorePrefix}%");
  let project = v("%{project}%");
  let store = v("%{store}%");
  let localStore = v("%{localStore}%");

  let toValue = path =>
    path |> show |> EsyLib.Path.normalizePathSepOfFilename |> Value.v;

  let toPath = (cfg, path) => path |> show |> render(cfg) |> v;

  let ofPath = (cfg, p) => {
    let p =
      if (isAbs(p)) {
        p;
      } else {
        cwd /\/ p;
      };
    let p = normalize(p);
    if (compare(p, cfg.storePath) == 0) {
      store;
    } else if (compare(p, cfg.localStorePath) == 0) {
      localStore;
    } else if (compare(p, cfg.projectPath) == 0) {
      project;
    } else {
      switch (remPrefix(cfg.storePath, p)) {
      | Some(suffix) => normalizeAndRemoveEmptySeg(store /\/ suffix)
      | None =>
        switch (remPrefix(cfg.localStorePath, p)) {
        | Some(suffix) => normalizeAndRemoveEmptySeg(localStore /\/ suffix)
        | None =>
          switch (remPrefix(cfg.projectPath, p)) {
          | Some(suffix) => normalizeAndRemoveEmptySeg(project /\/ suffix)
          | None => p
          }
        }
      };
    };
  };
};

module Environment = EsyLib.Environment.Make(Value);
