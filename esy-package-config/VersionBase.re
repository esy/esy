module type VERSION = {
  type t;

  include S.COMMON with type t := t;

  let parser: Parse.t(t);
  let parse: string => result(t, string);
  let parseExn: string => t;

  let majorMinorPatch: t => option((int, int, int));
  let prerelease: t => bool;
  let stripPrerelease: t => t;
};

module type CONSTRAINT = {
  type version;

  type t =
    | EQ(version)
    | NEQ(version)
    | GT(version)
    | GTE(version)
    | LT(version)
    | LTE(version)
    | ANY;

  include S.COMMON with type t := t;

  module VersionSet: Set.S with type elt = version;

  let matchesSimple: (~version: version, t) => bool;

  let matches:
    (~matchPrerelease: VersionSet.t=?, ~version: version, t) => bool;

  let map: (~f: version => version, t) => t;
};

module type FORMULA = {
  type version;
  type constr;

  type conj('f) = list('f);
  type disj('f) = list('f);

  module DNF: {
    type t = disj(conj(constr));

    include S.COMMON with type t := t;

    let unit: constr => t;
    let matches: (~version: version, t) => bool;
    let map: (~f: version => version, t) => t;

    let conj: (t, t) => t;
    let disj: (disj(constr), disj(constr)) => disj(constr);
  };

  module CNF: {
    type t = conj(disj(constr));

    include S.COMMON with type t := t;

    let matches: (~version: version, t) => bool;
  };

  let ofDnfToCnf: DNF.t => CNF.t;

  module ParseUtils: {
    let conjunction: (~parse: string => 'a, string) => disj('a);
    let disjunction:
      (~parse: string => disj(constr), string) => disj(disj(constr));
  };
};

/** Constraints over versions */
module Constraint = {
  module Make =
         (Version: VERSION)
         : (CONSTRAINT with type version = Version.t) => {
    module VersionSet = Set.Make(Version);

    type version = Version.t;

    [@deriving (yojson, ord)]
    type t =
      | EQ(Version.t)
      | NEQ(Version.t)
      | GT(Version.t)
      | GTE(Version.t)
      | LT(Version.t)
      | LTE(Version.t)
      | ANY;

    let pp = fmt =>
      fun
      | EQ(v) => Fmt.pf(fmt, "=%a", Version.pp, v)
      | NEQ(v) => Fmt.pf(fmt, "!=%a", Version.pp, v)
      | GT(v) => Fmt.pf(fmt, ">%a", Version.pp, v)
      | GTE(v) => Fmt.pf(fmt, ">=%a", Version.pp, v)
      | LT(v) => Fmt.pf(fmt, "<%a", Version.pp, v)
      | LTE(v) => Fmt.pf(fmt, "<=%a", Version.pp, v)
      | ANY => Fmt.pf(fmt, "*");

    let matchesSimple = (~version, constr) =>
      switch (constr) {
      | EQ(a) => Version.compare(a, version) == 0
      | NEQ(a) => Version.compare(a, version) !== 0
      | ANY => true

      | GT(a) => Version.compare(a, version) < 0
      | GTE(a) => Version.compare(a, version) <= 0
      | LT(a) => Version.compare(a, version) > 0
      | LTE(a) => Version.compare(a, version) >= 0
      };

    let matches = (~matchPrerelease=VersionSet.empty, ~version, constr) =>
      switch (Version.prerelease(version), constr) {
      | (_, EQ(_))
      | (_, NEQ(_))
      | (false, ANY)
      | (false, GT(_))
      | (false, GTE(_))
      | (false, LT(_))
      | (false, LTE(_)) => matchesSimple(~version, constr)

      | (true, ANY)
      | (true, GT(_))
      | (true, GTE(_))
      | (true, LT(_))
      | (true, LTE(_)) =>
        if (VersionSet.mem(Version.stripPrerelease(version), matchPrerelease)) {
          matchesSimple(~version, constr);
        } else {
          false;
        }
      };

    let show = v => Format.asprintf("%a", pp, v);

    let rec map = (~f, constr) =>
      switch (constr) {
      | EQ(a) => EQ(f(a))
      | NEQ(a) => NEQ(f(a))
      | ANY => ANY
      | GT(a) => GT(f(a))
      | GTE(a) => GTE(f(a))
      | LT(a) => LT(f(a))
      | LTE(a) => LTE(f(a))
      };
  };
};

module Formula = {
  module Make =
         (
           Version: VERSION,
           Constraint: CONSTRAINT with type version = Version.t,
         )

           : (
             FORMULA with
               type version = Constraint.version and type constr = Constraint.t
         ) => {
    type version = Constraint.version;
    type constr = Constraint.t;

    [@ocaml.warning "-32"];
    [@deriving (show, yojson, ord)]
    type conj('f) = list('f);

    [@ocaml.warning "-32"];
    [@deriving (show, yojson, ord)]
    type disj('f) = list('f);

    module VersionSet = Constraint.VersionSet;

    module DNF = {
      [@deriving (yojson, ord)]
      type t = disj(conj(Constraint.t));

      let unit = constr => [[constr]];

      let matches = (~version, formulas) => {
        let matchesConj = formulas => {
          /* Within each conjunction we allow prelease versions to be matched
           * but only those were mentioned in any of the constraints of the
           * conjunction, so that:
           *  1.0.0-alpha.2 matches >=1.0.0.alpha1
           *  1.0.0-alpha.2 does not match >=0.9.0
           *  1.0.0-alpha.2 does not match >=0.9.0 <2.0.0
           */
          let matchPrerelease = {
            let f = vs =>
              fun
              | Constraint.ANY => vs
              | Constraint.EQ(v)
              | Constraint.NEQ(v)
              | Constraint.LTE(v)
              | Constraint.LT(v)
              | Constraint.GTE(v)
              | Constraint.GT(v) =>
                if (Version.prerelease(v)) {
                  VersionSet.add(Version.stripPrerelease(v), vs);
                } else {
                  vs;
                };

            List.fold_left(~f, ~init=VersionSet.empty, formulas);
          };

          List.for_all(
            ~f=Constraint.matches(~matchPrerelease, ~version),
            formulas,
          );
        };

        List.exists(~f=matchesConj, formulas);
      };

      let pp = (fmt, f) => {
        let ppConjDefault = Fmt.(list(~sep=any(" "), Constraint.pp));
        let ppConj = (fmt, conj) =>
          switch (conj) {
          | [Constraint.GTE(a), Constraint.LT(b)] =>
            switch (
              Version.majorMinorPatch(a),
              Version.majorMinorPatch(b),
              Version.prerelease(b),
            ) {
            | (Some((0, aMinor, _)), Some((0, bMinor, 0)), false)
                when bMinor - aMinor == 1 =>
              Fmt.pf(fmt, "^%a", Version.pp, a)
            | (Some((aMajor, _, _)), Some((bMajor, 0, 0)), false)
                when aMajor > 0 && bMajor > 0 && bMajor - aMajor == 1 =>
              Fmt.pf(fmt, "^%a", Version.pp, a)
            | _ => ppConjDefault(fmt, conj)
            }
          | _ => ppConjDefault(fmt, conj)
          };

        Fmt.(list(~sep=any(" || "), ppConj))(fmt, f);
      };

      let show = f => Format.asprintf("%a", pp, f);

      let rec map = (~f, formulas) => {
        let mapConj = formulas => List.map(~f=Constraint.map(~f), formulas);
        List.map(~f=mapConj, formulas);
      };

      let conj = (a, b) => {
        let items = {
          let items = [];
          let f = (items, a) => {
            let f = (items, b) => [a @ b, ...items];

            List.fold_left(~f, ~init=items, b);
          };

          List.fold_left(~f, ~init=items, a);
        };
        items;
      };

      let disj = (a, b) => a @ b;
    };

    module CNF = {
      [@ocaml.warning "-32"];
      [@deriving (yojson, ord)]
      type t = conj(disj(Constraint.t));

      let pp = (fmt, f) => {
        let ppDisj = fmt =>
          fun
          | [] => Fmt.any("true", fmt, ())
          | [disj] => Constraint.pp(fmt, disj)
          | disjs =>
            Fmt.pf(
              fmt,
              "(%a)",
              Fmt.(list(~sep=any(" || "), Constraint.pp)),
              disjs,
            );

        Fmt.(list(~sep=any(" && "), ppDisj))(fmt, f);
      };

      let show = f => Format.asprintf("%a", pp, f);

      let matches = (~version, formulas) => {
        let matchesDisj = formulas => {
          /* Within each conjunction we allow prelease versions to be matched
           * but only those were mentioned in any of the constraints of the
           * conjunction, so that:
           *  1.0.0-alpha.2 matches >=1.0.0.alpha1
           *  1.0.0-alpha.2 does not match >=0.9.0
           *  1.0.0-alpha.2 does not match >=0.9.0 <2.0.0
           */
          let matchPrerelease = {
            let f = vs =>
              fun
              | Constraint.ANY => vs
              | Constraint.EQ(v)
              | Constraint.NEQ(v)
              | Constraint.LTE(v)
              | Constraint.LT(v)
              | Constraint.GTE(v)
              | Constraint.GT(v) =>
                if (Version.prerelease(v)) {
                  VersionSet.add(Version.stripPrerelease(v), vs);
                } else {
                  vs;
                };

            List.fold_left(~f, ~init=VersionSet.empty, formulas);
          };

          List.exists(
            ~f=Constraint.matches(~matchPrerelease, ~version),
            formulas,
          );
        };

        List.for_all(~f=matchesDisj, formulas);
      };
    };

    let ofDnfToCnf = (f: DNF.t) => {
      let f: CNF.t = (
        switch (f) {
        | [] => []
        | [constrs, ...conjs] =>
          let init: list(disj(constr)) = (
            List.map(~f=r => [r], constrs): list(disj(constr))
          );
          let conjs = {
            let addConj = (cnf: list(disj(constr)), conj) =>
              cnf
              |> List.map(~f=constrs =>
                   List.map(~f=r => [r, ...constrs], conj)
                 )
              |> List.flatten;

            List.fold_left(~f=addConj, ~init, conjs);
          };

          conjs;
        }: CNF.t
      );
      f;
    };

    module ParseUtils = {
      let conjunction = (~parse, item) => {
        let item =
          item
          |> Str.global_replace(Str.regexp(">= +"), ">=")
          |> Str.global_replace(Str.regexp("<= +"), "<=")
          |> Str.global_replace(Str.regexp("> +"), ">")
          |> Str.global_replace(Str.regexp("< +"), "<");

        let items = String.split_on_char(' ', item);
        List.map(~f=parse, items);
      };

      let disjunction = (~parse, version) => {
        let version = String.trim(version);
        let items = Str.split(Str.regexp(" +|| +"), version);
        let items = List.map(~f=parse, items);
        let items =
          switch (items) {
          | [] => [[Constraint.ANY]]
          | items => items
          };

        items;
      };
    };
  };
};

let%test_module "Formula" =
  (module
   {
     module Version = {
       [@deriving yojson]
       type t = int;
       let majorMinorPatch = n => Some((n, 0, 0));
       let compare = compare;
       let pp = Fmt.int;
       let show = string_of_int;
       let prerelease = _ => false;
       let stripPrerelease = v => v;
       let parser =
         Parse.(
           take_while1(
             fun
             | '0' .. '9' => true
             | _ => false,
           )
           >>| int_of_string
         );
       let parse = v =>
         switch (int_of_string_opt(v)) {
         | Some(v) => Ok(v)
         | None => Error("not a version")
         };
       let parseExn = int_of_string;
     };

     module C = Constraint.Make(Version);
     module F = Formula.Make(Version, C);
     open C;

     let%test "ofDnfToCnf: 1" = F.ofDnfToCnf([[C.EQ(1)]]) == [[EQ(1)]];

     let%test "ofDnfToCnf: 1 && 2" =
       F.ofDnfToCnf([[EQ(1), EQ(2)]]) == [[EQ(1)], [EQ(2)]];

     let%test "ofDnfToCnf: 1 && 2 || 3" =
       F.ofDnfToCnf([[EQ(1), EQ(2)], [EQ(3)]])
       == [[EQ(3), EQ(1)], [EQ(3), EQ(2)]];

     let%test "ofDnfToCnf: 1 && 2 || 3 && 4" =
       F.ofDnfToCnf([[EQ(1), EQ(2)], [EQ(3), EQ(4)]])
       == [
            [EQ(3), EQ(1)],
            [EQ(4), EQ(1)],
            [EQ(3), EQ(2)],
            [EQ(4), EQ(2)],
          ];
   });
