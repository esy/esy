

let parseConcrete = Npm.OpamConcrete.parseConcrete;
let triple = Npm.OpamConcrete.triple;

let fromPrefix = (op, version) => {
  open Shared.GenericVersion;
  let v = Npm.NpmVersion.parseConcrete(version);
  switch op {
  | `Eq => Exactly(v)
  | `Geq => AtLeast(v)
  | `Leq => AtMost(v)
  | `Lt => LessThan(v)
  | `Gt => GreaterThan(v)
  | `Neq => Or(GreaterThan(v), LessThan(v))
  }
};

let rec getOCamlVersion = opamvalue => {
  /* Shared.GenericVersion.Any */
  open OpamParserTypes;
  open Shared.GenericVersion;
  switch opamvalue {
  | Logop(_, `And, left, right) => {
    And(getOCamlVersion(left), getOCamlVersion(right))
  }
  | Logop(_, `Or, left, right) => Or(getOCamlVersion(left), getOCamlVersion(right))
  | Relop(_, rel, Ident(_, "ocaml-version"), String(_, version)) => fromPrefix(rel, version)
  /* We don't support pre-4.02.3 anyway */
  | Relop(_, `Neq, Ident(_, "compiler"), String(_, "4.02.1+BER")) => Any
  | Relop(_, `Eq, Ident(_, "compiler"), String(_, _)) => Any
  | Relop(_, _rel, Ident(_, "opam-version"), _) => Any /* TODO should I care about this? */
  | Relop(_, rel, Ident(_, "os"), String(_, version)) => Any
  | Pfxop(_, `Not, Ident(_, "preinstalled")) => Any
  | Ident(_, "preinstalled" | "false") => Any
  | Bool(_, true) => Any
  | Bool(_, false) => Nothing
  | Option(_, contents, options) => {
    print_endline("Ignoring option: " ++ (options |> List.map(OpamPrinter.value) |> String.concat(" .. ")));
    getOCamlVersion(contents)
  }
  | List(_, items) => {
    let rec loop = items => switch items {
    | [] => Any
    | [item] => getOCamlVersion(item)
    | [item, ...rest] => And(getOCamlVersion(item), loop(rest))
    };
    loop(items)
  }
  | Group(_, items) => {
    let rec loop = items => switch items {
    | [] => Any
    | [item] => getOCamlVersion(item)
    | [item, ...rest] => And(getOCamlVersion(item), loop(rest))
    };
    loop(items)
  }
  | y => {
    print_endline("Unexpected option -- pretending its any " ++ OpamPrinter.value(opamvalue));
    Any
  }
  }
};


let rec getAvailability = opamvalue => {
  /* Shared.GenericVersion.Any */
  open OpamParserTypes;
  switch opamvalue {
  | Logop(_, `And, left, right) => {
    getAvailability(left) && getAvailability(right)
  }
  | Logop(_, `Or, left, right) => getAvailability(left) || getAvailability(right)
  | Relop(_, rel, Ident(_, "ocaml-version"), String(_, version)) => true
  /* We don't support pre-4.02.3 anyway */
  | Relop(_, `Neq, Ident(_, "compiler"), String(_, "4.02.1+BER")) => true
  | Relop(_, `Eq, Ident(_, "compiler"), String(_, compiler)) => {
    /* print_endline("Wants a compiler " ++ compiler ++ "... assuming we don't have it"); */
    false
  }
  | Relop(_, _rel, Ident(_, "opam-version"), _) => true
  | Relop(_, `Eq, Ident(_, "os"), String(_, "darwin")) => true
  | Relop(_, `Neq, Ident(_, "os"), String(_, "darwin")) => false
  | Relop(_, rel, Ident(_, "os"), String(_, os)) => false
  | Pfxop(_, `Not, Ident(_, "preinstalled")) => true
  | Ident(_, "preinstalled") => false
  | Bool(_, false) => false
  | Bool(_, true) => true
  | Option(_, contents, options) => {
    print_endline("[[ AVAILABILITY ]] Ignoring option: " ++ (options |> List.map(OpamPrinter.value) |> String.concat(" .. ")));
    getAvailability(contents)
  }
  | List(_, items) => {
    let rec loop = items => switch items {
    | [] => true
    | [item] => getAvailability(item)
    | [item, ...rest] => getAvailability(item) && loop(rest)
    };
    loop(items)
  }
  | Group(_, items) => {
    let rec loop = items => switch items {
    | [] => true
    | [item] => getAvailability(item)
    | [item, ...rest] => getAvailability(item) && loop(rest)
    };
    loop(items)
  }
  | y => {
    print_endline("Unexpected availability option -- pretending its fine " ++ OpamPrinter.value(opamvalue));
    true
  }
  }
};
