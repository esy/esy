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
