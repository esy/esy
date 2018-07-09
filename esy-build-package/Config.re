[@deriving show]
type t = {
  sandboxPath: Fpath.t,
  storePath: Fpath.t,
  localStorePath: Fpath.t,
  rsyncCmd: string,
  fastreplacestringCmd: string,
};

let storeInstallTree = "i";

let storeBuildTree = "b";

let storeStageTree = "s";

let storeVersion = "3";

let maxStorePaddingLength = {
  /*
   * This is restricted by POSIX, Linux enforces this but macOS is more
   * forgiving.
   */
  let maxShebangLength = 127;
  /*
   * We reserve that amount of chars from padding so ocamlrun can be placed in
   * shebang lines
   */
  let ocamlrunStorePath = "ocaml-n.00.000-########/bin/ocamlrun";
  maxShebangLength
  - String.length("!#")
  - String.length(
      "/"
      ++ storeVersion
      ++ "/"
      ++ storeInstallTree
      ++ "/"
      ++ ocamlrunStorePath,
    );
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
      let storePadding = {
        /* TODO: Fork for windows */
        /* let prefixPathLength = String.length(Fpath.to_string(prefixPath)); */
        /* let paddingLength = maxStorePaddingLength - prefixPathLength; */
        String.make(1, '_');
      };
      let storePath = prefixPath / (storeVersion ++ storePadding);
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
