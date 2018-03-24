/**
 * Compiler toolchains.
 **/
module ConfigPath = Config.ConfigPath;

[@deriving (show, eq, ord)]
type toolchain =
  | Native
  | Target(string);

[@deriving (show, eq, ord)]
type findlib = {
  path: string,
  destdir: string,
  stdlib: string,
  ldconf: string,
  commands: list((string, string)),
};

[@deriving (show, eq, ord)]
type t =
  | Ocamlfind(toolchain, findlib);

let compilers = ["ocaml", "ocaml-ios"];

let isCompiler = (pkg: Package.t) => List.mem(pkg.name, compilers);

let ocamlfindCommands = prefix =>
  [
    "ocamlc",
    "ocamlopt",
    "ocamlcp",
    "ocamlmklib",
    "ocamlmktop",
    "ocamldoc",
    "ocamldep",
    "ocamllex",
  ]
  |> List.map(cmd => (cmd, ConfigPath.(prefix / cmd |> toString)));

let toConfigVar = (toolchain, name, value) => {
  let field =
    switch (toolchain) {
    | Native => name
    | Target(target) => name ++ "(" ++ target ++ ")"
    };
  field ++ " = \"" ++ value ++ "\"";
};

let findlibFilename = (~prefix: ConfigPath.t) =>
  fun
  | Ocamlfind(Native, _) => ConfigPath.(prefix / "findlib.conf" |> toString)
  | Ocamlfind(Target(target), _) =>
    ConfigPath.(prefix / "findlib.conf.d" / (target ++ ".conf") |> toString);

let findlibContents =
  fun
  | Ocamlfind(toolchain, findlib) =>
    String.concat(
      "\n",
      [
        toConfigVar(toolchain, "path", findlib.path),
        toConfigVar(toolchain, "destdir", findlib.destdir),
        toConfigVar(toolchain, "stdlib", findlib.stdlib),
        toConfigVar(toolchain, "ldconf", findlib.ldconf),
      ]
      @ List.map(
          ((name, cmd)) => toConfigVar(toolchain, name, cmd),
          findlib.commands,
        ),
    );
