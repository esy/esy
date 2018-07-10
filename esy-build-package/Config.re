module Store = EsyLib.Store;

[@deriving show]
type t = {
  sandboxPath: Fpath.t,
  storePath: Fpath.t,
  localStorePath: Fpath.t,
  rsyncCmd: string,
  fastreplacestringCmd: string,
};

/**
 * Initialize config optionally with prefixPath and sandboxPath.
 *
 * If prefixPath is not provided then ~/.esy is used.
 * If sandboxPath is not provided then $PWD us used.
 */
let create =
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
      let storePath = prefixPath / (Store.version ++ Store.getPadding(prefixPath));
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
