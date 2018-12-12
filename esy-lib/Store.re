include Fpath;

let installTree = "i";

let buildTree = "b";

let stageTree = "s";

let version = "3";

let maxStorePaddingLength = {
  /*
   * This is restricted by POSIX, Linux enforces this but macOS is more
   * forgiving.
   */
  let maxShebangLength = Sys.win32 ? 75 : 127;
  /*
   * We reserve that amount of chars from padding so ocamlrun can be placed in
   * shebang lines
   */
  let ocamlrunStorePath = "ocaml-n.00.000-########/bin/ocamlrun";
  maxShebangLength
  - String.length("!#")
  - String.length(
      "/" ++ version ++ "/" ++ installTree ++ "/" ++ ocamlrunStorePath,
    );
};

let getPadding = (prefixPath) => {
  let prefixPathLength = String.length(Fpath.to_string(prefixPath));
  let paddingLength = maxStorePaddingLength - prefixPathLength;

  if (paddingLength < 0) {
    Error(`Msg("prefixPath is too deep in the filesystem"));
  } else {
    Ok(String.make(paddingLength, '_'));
  };
};
