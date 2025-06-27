include Fpath;

let installTree = "i";

let buildTree = "b";

let stageTree = "s";

// Must be updated every time we make changes to how artifacts are installed
// otherwise users complain that they don't see a fix/patch working
let version = "4"; 

let maxStorePaddingLength = (~ocamlPkgName, ~ocamlVersion, ()) => {
  /*
   * This is restricted by POSIX, Linux enforces this but macOS is more
   * forgiving.
   */
  let maxShebangLength = 127;
  /*
   * We reserve that amount of chars from padding so ocamlrun can be placed in
   * shebang lines
   */
  let ocamlrunStorePath =
    ocamlPkgName ++ "-" ++ ocamlVersion ++ "-########/bin/ocamlrun";
  maxShebangLength
  - String.length("!#")
  - String.length(
      "/" ++ version ++ "/" ++ installTree ++ "/" ++ ocamlrunStorePath,
    );
};

let getPadding =
    (
      ~system=System.Platform.host,
      ~longPaths=System.supportsLongPaths(),
      ~ocamlPkgName,
      ~ocamlVersion,
      prefixPath,
    ) =>
  switch (system, longPaths) {
  | (Windows, false) => Ok("_")
  | _ =>
    let prefixPathLength = String.length(Fpath.to_string(prefixPath));
    let paddingLength =
      maxStorePaddingLength(~ocamlPkgName, ~ocamlVersion, ())
      - prefixPathLength;

    if (paddingLength < 0) {
      Error(`Msg("prefixPath is too deep in the filesystem"));
    } else {
      Ok(String.make(paddingLength, '_'));
    };
  };
