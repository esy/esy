module Store = EsyLib.Store;
module Path = EsyLib.Path;

type t = {
  sandboxPath: Fpath.t,
  storePath: Fpath.t,
  localStorePath: Fpath.t,
  rsyncCmd: string,
  fastreplacestringCmd: string,
};

type config = t;

/**
 * Initialize config optionally with prefixPath and sandboxPath.
 *
 * If prefixPath is not provided then ~/.esy is used.
 * If sandboxPath is not provided then $PWD us used.
 */
let make =
    (
      ~prefixPath,
      ~sandboxPath,
      ~rsyncCmd="rsync",
      ~fastreplacestringCmd="fastreplacestring.exe",
      (),
    ) =>
  Run.(
    {
      let%bind prefixPath =
        switch (prefixPath) {
        | Some(v) => Ok(v)
        | None =>
          let%bind home = Bos.OS.Dir.user();
          Ok(home / ".esy");
        };
      let%bind sandboxPath =
        switch (sandboxPath) {
        | Some(v) => Ok(v)
        | None => Bos.OS.Dir.current()
        };
      let%bind padding = Store.getPadding(prefixPath);
      let storePath = prefixPath / (Store.version ++ padding);
      let localStorePath =
        sandboxPath / "node_modules" / ".cache" / "_esy" / "store";
      Ok({
        storePath,
        sandboxPath,
        localStorePath,
        fastreplacestringCmd,
        rsyncCmd,
      });
    }
  );

module Value = {
  type t = string;

  let sandbox = "%sandbox%";
  let store = "%store%";
  let localStore = "%localStore%";

  let show = v => v;
  let pp = Fmt.string;
  let equal = String.equal;

  let v = v => v;

  let toString = (~cfg, v) => {
    let lookupVar =
      fun
      | "sandbox" => Some(Path.to_string(cfg.sandboxPath))
      | "store" => Some(Path.to_string(cfg.storePath))
      | "localStore" => Some(Path.to_string(cfg.localStorePath))
      | _ => None;
    PathSyntax.render(lookupVar, v);
  };

  let of_yojson = EsyLib.Json.Parse.string;
  let to_yojson = v => `String(v);
};
