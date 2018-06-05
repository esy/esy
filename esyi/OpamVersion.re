let fromPrefix = (op, version) => {
  open GenericVersion;
  let v = OpamVersioning.Version.parseExn(version);
  switch (op) {
  | `Eq => Exactly(v)
  | `Geq => AtLeast(v)
  | `Leq => AtMost(v)
  | `Lt => LessThan(v)
  | `Gt => GreaterThan(v)
  | `Neq => failwith("Can't do neq in opam version constraints")
  };
};

let rec parseRange = opamvalue =>
  OpamParserTypes.(
    GenericVersion.(
      switch (opamvalue) {
      | Prefix_relop(_, op, String(_, version)) => fromPrefix(op, version)
      | Logop(_, `And, left, right) =>
        And(parseRange(left), parseRange(right))
      | Logop(_, `Or, left, right) =>
        Or(parseRange(left), parseRange(right))
      | String(_, version) =>
        Exactly(OpamVersioning.Version.parseExn(version))
      | Option(_, contents, options) =>
        print_endline(
          "Ignoring option: "
          ++ (
            options |> List.map(OpamPrinter.value) |> String.concat(" .. ")
          ),
        );
        parseRange(contents);
      | _y =>
        print_endline(
          "Unexpected option -- pretending its any "
          ++ OpamPrinter.value(opamvalue),
        );
        Any;
      }
    )
  );

let rec toDep = opamvalue =>
  OpamParserTypes.(
    GenericVersion.(
      switch (opamvalue) {
      | String(_, name) => (name, Any, `Link)
      | Option(_, String(_, name), [Ident(_, "build")]) => (
          name,
          Any,
          `Build,
        )
      | Option(
          _,
          String(_, name),
          [Logop(_, `And, Ident(_, "build"), version)],
        ) => (
          name,
          parseRange(version),
          `Build,
        )
      | Option(_, String(_, name), [Ident(_, "test")]) => (
          name,
          Any,
          `Test,
        )
      | Option(
          _,
          String(_, name),
          [Logop(_, `And, Ident(_, "test"), version)],
        ) => (
          name,
          parseRange(version),
          `Test,
        )
      | Group(_, [Logop(_, `Or, String(_, "base-no-ppx"), otherThing)]) =>
        /* yep we allow ppxs */
        toDep(otherThing)
      | Group(_, [Logop(_, `Or, String(_, one), String(_, two))]) =>
        print_endline(
          "Arbitrarily choosing the second of two options: "
          ++ one
          ++ " and "
          ++ two,
        );
        (two, Any, `Link);
      | Group(_, [Logop(_, `Or, first, second)]) =>
        print_endline(
          "Arbitrarily choosing the first of two options: "
          ++ OpamPrinter.value(first)
          ++ " and "
          ++ OpamPrinter.value(second),
        );
        toDep(first);
      | Option(_, String(_, name), [option]) => (
          name,
          parseRange(option),
          `Link,
        )
      | _ =>
        failwith(
          "Can't parse this opam dep " ++ OpamPrinter.value(opamvalue),
        )
      }
    )
  );
