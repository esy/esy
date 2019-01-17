module Store = EsyLib.Store;

[@deriving (show, to_yojson)]
type t = {
  projectPath: EsyLib.Path.t,
  storePath: EsyLib.Path.t,
  localStorePath: EsyLib.Path.t,
};

type config = t;

type storePathConfig =
  | StorePath(Fpath.t)
  | StorePathOfPrefix(Fpath.t)
  | StorePathDefault;

let cwd = EsyLib.Path.v(Sys.getcwd());

let initStore = (path: Fpath.t) => {
  open Run;
  let%bind () = mkdir(Fpath.(path / "i"));
  let%bind () = mkdir(Fpath.(path / "b"));
  let%bind () = mkdir(Fpath.(path / "s"));
  return();
};

let rec configureStorePath = cfg => {
  open Run;
  let%bind path =
    switch (cfg) {
    | StorePath(storePath) => return(storePath)
    | StorePathOfPrefix(prefixPath) =>
      let%bind padding = Store.getPadding(prefixPath);
      let storePath = prefixPath / (Store.version ++ padding);
      return(storePath);
    | StorePathDefault =>
      let home = EsyLib.Path.homePath();
      let prefixPath = home / ".esy";
      configureStorePath(StorePathOfPrefix(prefixPath));
    };
  let%bind () = initStore(path);
  return(path);
};

let make = (~storePath, ~projectPath, ~localStorePath, ()) => {
  open Run;
  let%bind storePath = configureStorePath(storePath);
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
  return({projectPath, storePath, localStorePath});
};

let render = (cfg, v) => {
  let path = v =>
    v |> EsyLib.Path.show |> EsyLib.Path.normalizePathSepOfFilename;
  let projectPath = path(cfg.projectPath);
  let storePath = path(cfg.storePath);
  let localStorePath = path(cfg.localStorePath);
  let lookupVar =
    fun
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

  let project = v("%{project}%");
  let store = v("%{store}%");
  let localStore = v("%{localStore}%");
};

module Path: {
  include EsyLib.Abstract.PATH with type ctx = config;
  let toValue: t => Value.t;
  let store: t;
  let localStore: t;
  let project: t;
} = {
  include EsyLib.Path;
  type ctx = config;

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
