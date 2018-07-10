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
      ++ version
      ++ "/"
      ++ installTree
      ++ "/"
      ++ ocamlrunStorePath,
    );
};

let getPadding = (~system=System.host, prefixPath) => {
    let paddingLength = switch (system) {
        | Windows => 1
        | _ => {
            let prefixPathLength = String.length(Fpath.to_string(prefixPath));
            maxStorePaddingLength - prefixPathLength;
        };
    };

    String.make(paddingLength, '_');
};
