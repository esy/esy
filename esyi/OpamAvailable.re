let fromPrefix = (op, version) => {
  open GenericVersion;
  let v = NpmVersion.parseConcrete(version);
  switch (op) {
  | `Eq => EQ(v)
  | `Geq => GTE(v)
  | `Leq => LTE(v)
  | `Lt => LT(v)
  | `Gt => GT(v)
  | `Neq => OR(GT(v), LT(v))
  };
};

let rec getOCamlVersion = opamvalue =>
  /* Shared.GenericVersion.ANY */
  OpamParserTypes.(
    GenericVersion.(
      switch (opamvalue) {
      | Logop(_, `And, left, right) =>
        AND(getOCamlVersion(left), getOCamlVersion(right))
      | Logop(_, `Or, left, right) =>
        OR(getOCamlVersion(left), getOCamlVersion(right))
      | Relop(_, rel, Ident(_, "ocaml-version"), String(_, version)) =>
        fromPrefix(rel, version)
      /* We don't support pre-4.02.3 anyway */
      | Relop(_, `Neq, Ident(_, "compiler"), String(_, "4.02.1+BER")) => ANY
      | Relop(_, `Eq, Ident(_, "compiler"), String(_, _)) => ANY
      | Relop(_, _rel, Ident(_, "opam-version"), _) => ANY /* TODO should I care about this? */
      | Relop(_, _rel, Ident(_, "os"), String(_, _version)) => ANY
      | Pfxop(_, `Not, Ident(_, "preinstalled")) => ANY
      | Ident(_, "preinstalled" | "false") => ANY
      | Bool(_, true) => ANY
      | Bool(_, false) => NONE
      | Option(_, contents, options) =>
        print_endline(
          "Ignoring option: "
          ++ (
            options |> List.map(OpamPrinter.value) |> String.concat(" .. ")
          ),
        );
        getOCamlVersion(contents);
      | List(_, items) =>
        let rec loop = items =>
          switch (items) {
          | [] => ANY
          | [item] => getOCamlVersion(item)
          | [item, ...rest] => AND(getOCamlVersion(item), loop(rest))
          };
        loop(items);
      | Group(_, items) =>
        let rec loop = items =>
          switch (items) {
          | [] => ANY
          | [item] => getOCamlVersion(item)
          | [item, ...rest] => AND(getOCamlVersion(item), loop(rest))
          };
        loop(items);
      | _y =>
        print_endline(
          "Unexpected option -- pretending its any "
          ++ OpamPrinter.value(opamvalue),
        );
        ANY;
      }
    )
  );

let rec getAvailability = opamvalue =>
  /* Shared.GenericVersion.ANY */
  OpamParserTypes.(
    switch (opamvalue) {
    | Logop(_, `And, left, right) =>
      getAvailability(left) && getAvailability(right)
    | Logop(_, `Or, left, right) =>
      getAvailability(left) || getAvailability(right)
    | Relop(_, _rel, Ident(_, "ocaml-version"), String(_, _version)) => true
    /* We don't support pre-4.02.3 anyway */
    | Relop(_, `Neq, Ident(_, "compiler"), String(_, "4.02.1+BER")) => true
    | Relop(_, `Eq, Ident(_, "compiler"), String(_, _compiler)) =>
      /* print_endline("Wants a compiler " ++ compiler ++ "... assuming we don't have it"); */
      false
    | Relop(_, _rel, Ident(_, "opam-version"), _) => true
    | Relop(_, `Eq, Ident(_, "os"), String(_, "darwin")) => true
    | Relop(_, `Neq, Ident(_, "os"), String(_, "darwin")) => false
    | Relop(_, _rel, Ident(_, "os"), String(_, _os)) => false
    | Pfxop(_, `Not, Ident(_, "preinstalled")) => true
    | Ident(_, "preinstalled") => false
    | Bool(_, false) => false
    | Bool(_, true) => true
    | Option(_, contents, options) =>
      print_endline(
        "[[ AVAILABILITY ]] Ignoring option: "
        ++ (options |> List.map(OpamPrinter.value) |> String.concat(" .. ")),
      );
      getAvailability(contents);
    | List(_, items) =>
      let rec loop = items =>
        switch (items) {
        | [] => true
        | [item] => getAvailability(item)
        | [item, ...rest] => getAvailability(item) && loop(rest)
        };
      loop(items);
    | Group(_, items) =>
      let rec loop = items =>
        switch (items) {
        | [] => true
        | [item] => getAvailability(item)
        | [item, ...rest] => getAvailability(item) && loop(rest)
        };
      loop(items);
    | _y =>
      print_endline(
        "Unexpected availability option -- pretending its fine "
        ++ OpamPrinter.value(opamvalue),
      );
      true;
    }
  );
