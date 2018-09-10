module Store = EsyLib.Store;

type t = {
  fastreplacestringPath: Fpath.t,
  projectPath: Fpath.t,
  sandboxPath: Fpath.t,
  storePath: Fpath.t,
  localStorePath: Fpath.t,
};

type config = t;

let cwd = EsyLib.Path.v(Sys.getcwd());

let make =
    (
      ~fastreplacestringPath=?,
      ~projectPath=?,
      ~sandboxPath=?,
      ~storePath=?,
      (),
    ) =>
  Run.(
    {
      let%bind projectPath =
        switch (projectPath) {
        | Some(v) => return(v)
        | None => Bos.OS.Dir.current()
        };
      let%bind storePath =
        switch (storePath) {
        | Some(v) => return(v)
        | None =>
          let home = EsyLib.Path.homePath();
          let prefixPath = home / ".esy";
          let%bind padding = Store.getPadding(prefixPath);
          return(prefixPath / (Store.version ++ padding));
        };
      let fastreplacestringPath =
        switch (fastreplacestringPath) {
        | Some(p) => p
        | None => Fpath.v("fastreplacestring.exe")
        };
      let sandboxPath =
        switch (sandboxPath) {
        | Some(v) => v
        | None => projectPath / "_esy" / "default"
        };
      let localStorePath = sandboxPath / "store";
      return({
        fastreplacestringPath,
        projectPath,
        sandboxPath,
        storePath,
        localStorePath,
      });
    }
  );

let render = (cfg, v) => {
  let path = v =>
    v |> EsyLib.Path.toString |> EsyLib.Path.normalizePathSlashes;
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
    } else if (equal(p, cfg.projectPath)) {
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
