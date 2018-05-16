
open Shared.Types;

let parseConcrete = Npm.OpamConcrete.parseConcrete;
let triple = Npm.OpamConcrete.triple;

let fromPrefix = (op, version) => {
  open Shared.GenericVersion;
  let v = parseConcrete(version);
  switch op {
  | `Eq => Exactly(v)
  | `Geq => AtLeast(v)
  | `Leq => AtMost(v)
  | `Lt => LessThan(v)
  | `Gt => GreaterThan(v)
  | `Neq => failwith("Can't do neq in opam version constraints")
  }
};

let rec parseRange = opamvalue => {
  open OpamParserTypes;
  open Shared.GenericVersion;
  switch opamvalue {
  | Prefix_relop(_, op, String(_, version)) => fromPrefix(op, version)
  | Logop(_, `And, left, right) => {
    And(parseRange(left), parseRange(right))
  }
  | Logop(_, `Or, left, right) => Or(parseRange(left), parseRange(right))
  | String(_, version) => Exactly(parseConcrete(version))
  | Option(_, contents, options) => {
    print_endline("Ignoring option: " ++ (options |> List.map(OpamPrinter.value) |> String.concat(" .. ")));
    parseRange(contents)
  }
  | y => {
    print_endline("Unexpected option -- pretending its any " ++
    OpamPrinter.value(opamvalue));
    Any
  }
  }
};

let rec toDep = opamvalue => {
  open OpamParserTypes;
  open Shared.GenericVersion;
  switch opamvalue {
  | String(_, name) => (name, Any, `Link)
  | Option(_, String(_, name), [Ident(_, "build")]) => (name, Any, `Build)
  | Option(_, String(_, name), [Logop(_, `And, Ident(_, "build"), version)]) => (name, parseRange(version), `Build)
  | Option(_, String(_, name), [Ident(_, "test")]) => (name, Any, `Test)
  | Option(_, String(_, name), [Logop(_, `And, Ident(_, "test"), version)]) => (name, parseRange(version), `Test)
  | Group(_, [Logop(_, `Or, String(_, "base-no-ppx"), otherThing)]) => {
    /* yep we allow ppxs */
    toDep(otherThing)
  }
  | Group(_, [Logop(_, `Or, String(_, one), String(_, two))]) => {
    print_endline("Arbitrarily choosing the second of two options: " ++ one ++ " and " ++ two);
    (two, Any, `Link)
  }
  | Group(_, [Logop(_, `Or, first, second)]) => {
    print_endline("Arbitrarily choosing the first of two options: " ++ OpamPrinter.value(first) ++ " and " ++ OpamPrinter.value(second));
    toDep(first)
  }
  | Option(_, String(_, name), [option]) => {
    (name, parseRange(option), `Link)
  }
  | _ => {
    failwith("Can't parse this opam dep " ++ OpamPrinter.value(opamvalue))
  }
  };
};

let splitInTwo = (string, char) => switch (String.split_on_char(char, string)) {
| [""] => `Empty
| [one] => `Just(one)
| [one, two] => `Two(one, two)
| [one, ...rest] => `Two(one, String.concat("~", rest))
};

[@test [
  (("a", "b"), -1),
  (("aa", "a"), 1),
  (("a~b", "a"), -1),
  (("", "~beta1"), 1)
]]
let compareWithTilde = (a, b) => {
  let atilde = String.contains(a, '~');
  let btilde = String.contains(b, '~');
  if (a == b) {
    0
  } else if (atilde || btilde) {
    switch (splitInTwo(a, '~'), splitInTwo(b, '~')) {
    | (`Empty, `Two("", _)) => 1
    | (`Two("", _), `Empty) => -1
    | (`Empty, _) => -1
    | (_, `Empty) => 1

    | (`Two(a, _), `Just(b)) when a == String.sub(b, 0, String.length(a)) => -1
    | (`Two(a, _), `Just(b)) => compare(a, String.sub(b, 0, String.length(a)))

    | (`Just(a), `Just(b)) => assert(false)

    | (`Just(a), `Two(b, _)) when String.sub(a, 0, String.length(b)) == b => -1
    | (`Just(a), `Two(b, _)) => compare(String.sub(a, 0, String.length(b)), b)

    | (`Two(a, aa), `Two(b, bb)) when a == b => compare(aa, bb)
    | (`Two(a, _), `Two(b, _)) => compare(a, b)
    };
  } else {
    compare(a, b)
  }
};

[@test [
  ((parseConcrete("1.2.3"), parseConcrete("1.2.4")), -1),
  ((parseConcrete("1.2.4"), parseConcrete("1.2.4")), 0),
  ((parseConcrete("1.2~alpha1"), parseConcrete("1.2.0~beta3")), -1),
  ((parseConcrete("1.2~alpha1"), parseConcrete("1.2")), -1),
]]
let rec compare = (Alpha(a, na), Alpha(b, nb)) => {
  if (a == b) {
    switch (na, nb) {
    | (None, None) => 0
    | (None, _) => -1
    | (_, None) => 1
    | (Some(na), Some(nb)) => compareNums(na, nb)
    }
  } else {
    compareWithTilde(a, b)
  }
} and compareNums = (Num(a, aa), Num(b, ab)) => {
  if (a == b) {
    switch (aa, ab) {
    | (None, None) => 0
    | (None, Some(Alpha(a, _))) when a != "" && a.[0] == '~' => 1
    | (Some(Alpha(a, _)), None) when a != "" && a.[0] == '~' => -1
    | (None, _) => -1
    | (_, None) => 1
    | (Some(aa), Some(ab)) => compare(aa, ab)
    }
  } else {
    a - b
  }
};

let rec viewAlpha = (Alpha(a, na)) => {
  switch na {
  | None => a
  | Some(b) => a ++ viewNum(b)
  }
} and viewNum = (Num(a, na)) => {
  string_of_int(a) ++ switch na {
  | None => ""
  | Some(a) => viewAlpha(a)
  }
};

let matches = Shared.GenericVersion.matches(compare);

let viewRange = Shared.GenericVersion.view(viewAlpha);