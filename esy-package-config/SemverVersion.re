module P = Parse;

module Version = {
  open Sexplib0.Sexp_conv;

  [@deriving sexp_of]
  type t = {
    major: int,
    minor: int,
    patch: int,
    prerelease,
    build,
  }
  and prerelease = list(segment)
  and build = list(string)
  and segment =
    | W(string)
    | N(int);

  let ppSegment = fmt =>
    fun
    | W(v) => Fmt.string(fmt, v)
    | N(v) => Fmt.int(fmt, v);

  let ppPrerelease = Fmt.(list(~sep=any("."), ppSegment));

  let ppBuild = Fmt.(list(~sep=any("."), string));

  let compareSegment = (a, b) =>
    switch (a, b) {
    | (N(_), W(_)) => (-1)
    | (W(_), N(_)) => 1
    | (N(a), N(b)) => compare(a, b)
    | (W(a), W(b)) => String.compare(a, b)
    };

  let make = (~prerelease=[], ~build=[], major, minor, patch) => {
    major,
    minor,
    patch,
    prerelease,
    build,
  };

  let show = v => {
    let prelease =
      switch (v.prerelease) {
      | [] => ""
      | v => Format.asprintf("-%a", ppPrerelease, v)
      };

    let build =
      switch (v.build) {
      | [] => ""
      | v => Format.asprintf("+%a", ppBuild, v)
      };

    Format.asprintf(
      "%i.%i.%i%s%s",
      v.major,
      v.minor,
      v.patch,
      prelease,
      build,
    );
  };

  let pp = (fmt, v) => Fmt.pf(fmt, "%s", show(v));

  let majorMinorPatch = v => Some((v.major, v.minor, v.patch));

  let prerelease = v =>
    switch (v.prerelease, v.build) {
    | ([], []) => false
    | (_, _) => true
    };

  let stripPrerelease = v => {...v, prerelease: [], build: []};

  module Parse = {
    open Re;
    let dot = char('.');
    let dash = char('-');
    let plus = char('+');
    let section = group(rep1(digit));
    let prereleaseChar = alt([alnum, char('-'), char('.')]);
    let prerelease = opt(seq([opt(dash), group(rep1(prereleaseChar))]));
    let build = opt(seq([opt(plus), group(rep1(prereleaseChar))]));
    let prefix = rep(alt([char('v'), char('=')]));

    let version3 =
      compile(
        seq([
          bos,
          prefix,
          section,
          dot,
          section,
          dot,
          section,
          prerelease,
          build,
          eos,
        ]),
      );

    let version2 =
      compile(
        seq([bos, prefix, section, dot, section, prerelease, build, eos]),
      );

    let version1 =
      compile(seq([bos, prefix, section, prerelease, build, eos]));

    let prerelaseAndBuild = compile(seq([bos, prerelease, build, eos]));
  };

  let intAtExn = (n, m) => {
    let v = Re.Group.get(m, n);
    int_of_string(v);
  };

  let optStrignAt = (n, m) =>
    switch (Re.Group.get(m, n)) {
    | exception Not_found => None
    | "" => None
    | v => Some(v)
    };

  let parsePrerelease = v =>
    v
    |> String.split_on_char('.')
    |> List.map(~f=v =>
         try(N(int_of_string(v))) {
         | _ => W(v)
         }
       );

  let parseBuild = v => String.split_on_char('.', v);

  let parsePrerelaseAndBuild = v =>
    switch (Re.exec_opt(Parse.prerelaseAndBuild, v)) {
    | Some(m) =>
      let prerelease =
        switch (optStrignAt(1, m)) {
        | Some(v) => parsePrerelease(v)
        | None => []
        };

      let build =
        switch (optStrignAt(2, m)) {
        | Some(v) => parseBuild(v)
        | None => []
        };

      [@implicit_arity] Ok(prerelease, build);
    | None =>
      let msg = Printf.sprintf("unable to parse prerelease part: %s", v);
      Error(msg);
    };

  let parse = version =>
    switch (Re.exec_opt(Parse.version3, version)) {
    | Some(m) =>
      let major = intAtExn(1, m);
      let minor = intAtExn(2, m);
      let patch = intAtExn(3, m);
      let prerelease =
        switch (optStrignAt(4, m)) {
        | Some(v) => parsePrerelease(v)
        | None => []
        };

      let build =
        switch (optStrignAt(5, m)) {
        | Some(v) => parseBuild(v)
        | None => []
        };

      Ok({major, minor, patch, prerelease, build});
    | None =>
      switch (Re.exec_opt(Parse.version2, version)) {
      | Some(m) =>
        let major = intAtExn(1, m);
        let minor = intAtExn(2, m);
        let prerelease =
          switch (optStrignAt(3, m)) {
          | Some(v) => parsePrerelease(v)
          | None => []
          };

        let build =
          switch (optStrignAt(4, m)) {
          | Some(v) => parseBuild(v)
          | None => []
          };

        Ok({major, minor, patch: 0, prerelease, build});
      | None =>
        switch (Re.exec_opt(Parse.version1, version)) {
        | Some(m) =>
          let major = intAtExn(1, m);
          let prerelease =
            switch (optStrignAt(2, m)) {
            | Some(v) => parsePrerelease(v)
            | None => []
            };

          let build =
            switch (optStrignAt(3, m)) {
            | Some(v) => parseBuild(v)
            | None => []
            };

          Ok({major, minor: 0, patch: 0, prerelease, build});
        | None =>
          let msg = Printf.sprintf("invalid semver version: '%s'", version);
          Error(msg);
        }
      }
    };

  let parseExn = v =>
    switch (parse(v)) {
    | Ok(v) => v
    | Error(err) => raise(Invalid_argument(err))
    };

  let parser = {
    let p = parse;
    open P;
    let* input = take_while1(_ => true);
    switch (p(input)) {
    | Ok(v) => return(v)
    | Error(msg) => fail(msg)
    };
  };

  let%test_module "parse" =
    (module
     {
       let expectParsesTo = (v, e) => {
         let p = parse(v);
         switch (e, p) {
         | (Error(_), Error(_)) => true
         | (Ok(e), Ok(p)) =>
           if (compare(p, e) == 0) {
             true;
           } else {
             Format.printf(
               "@[<v 2>Failed to parse: %s@\nexpected: %a@\n     got: %a@]@\n",
               v,
               pp,
               e,
               pp,
               p,
             );
             false;
           }
         | (Error(_), Ok(p)) =>
           Format.printf(
             "@[<v 2>Expected to error but it parses: %s@\nas: %a@]@\n",
             v,
             pp,
             p,
           );
           false;
         | (Ok(e), Error(_)) =>
           Format.printf(
             "@[<v 2>Expected to parse but it errors: %s@\nexpected: %a@]@\n",
             v,
             pp,
             e,
           );
           false;
         };
       };

       let cases = [
         ("1.1.1", Ok(make(1, 1, 1))),
         ("1.1", Ok(make(1, 1, 0))),
         ("1", Ok(make(1, 0, 0))),
         (
           "1.1.1-alpha.29",
           Ok(make(~prerelease=[W("alpha"), N(29)], 1, 1, 1)),
         ),
         (
           "1.1-alpha.29",
           Ok(make(~prerelease=[W("alpha"), N(29)], 1, 1, 0)),
         ),
         (
           "1-alpha.29",
           Ok(make(~prerelease=[W("alpha"), N(29)], 1, 0, 0)),
         ),
         ("v1.1.1", Ok(make(1, 1, 1))),
         ("v1.1", Ok(make(1, 1, 0))),
         ("v1", Ok(make(1, 0, 0))),
         ("=1.1.1", Ok(make(1, 1, 1))),
         ("=1.1", Ok(make(1, 1, 0))),
         ("=1", Ok(make(1, 0, 0))),
         ("==1.1.1", Ok(make(1, 1, 1))),
         ("=v1.1.1", Ok(make(1, 1, 1))),
         ("=vv1.1.1", Ok(make(1, 1, 1))),
         ("==vv1.1.1", Ok(make(1, 1, 1))),
         (
           "1.1.1alpha.29",
           Ok(make(~prerelease=[W("alpha"), N(29)], 1, 1, 1)),
         ),
         (
           "1.1.1-alpha.029",
           Ok(make(~prerelease=[W("alpha"), N(29)], 1, 1, 1)),
         ),
         (
           "1.1.1-alpha.29+1.a",
           Ok(
             make(
               ~prerelease=[W("alpha"), N(29)],
               ~build=["1", "a"],
               1,
               1,
               1,
             ),
           ),
         ),
         (
           "1.1-alpha.29+1.a",
           Ok(
             make(
               ~prerelease=[W("alpha"), N(29)],
               ~build=["1", "a"],
               1,
               1,
               0,
             ),
           ),
         ),
         (
           "1-alpha.29+1.a",
           Ok(
             make(
               ~prerelease=[W("alpha"), N(29)],
               ~build=["1", "a"],
               1,
               0,
               0,
             ),
           ),
         ),
         ("1.1.1+1.a", Ok(make(~build=["1", "a"], 1, 1, 1))),
         ("1.1+1.a", Ok(make(~build=["1", "a"], 1, 1, 0))),
         ("1+1.a", Ok(make(~build=["1", "a"], 1, 0, 0))),
         ("1.1.1+001.002", Ok(make(~build=["001", "002"], 1, 1, 1))),
         ("a", Error("err")),
         ("latest", Error("latest")),
         ("1._", Error("err")),
       ];

       let%test "parsing" = {
         let f = (passes, (v, e)) => passes && expectParsesTo(v, e);

         List.fold_left(~f, ~init=true, cases);
       };
     });

  let comparePrerelease = (a: list(segment), b: list(segment)) => {
    let rec compare = (a, b) =>
      switch (a, b) {
      | ([], []) => 0
      | ([], _) => (-1)
      | (_, []) => 1
      | ([x, ...xs], [y, ...ys]) =>
        switch (compareSegment(x, y)) {
        | 0 => compare(xs, ys)
        | v => v
        }
      };

    switch (a, b) {
    | ([], []) => 0
    | ([], _) => 1
    | (_, []) => (-1)
    | (a, b) => compare(a, b)
    };
  };

  let compareBuild = (a: list(string), b: list(string)) => {
    let rec compare = (a, b) =>
      switch (a, b) {
      | ([], []) => 0
      | ([], _) => (-1)
      | (_, []) => 1
      | ([x, ...xs], [y, ...ys]) =>
        switch (String.compare(x, y)) {
        | 0 => compare(xs, ys)
        | v => v
        }
      };

    switch (a, b) {
    | ([], []) => 0
    | ([], _) => 1
    | (_, []) => (-1)
    | (a, b) => compare(a, b)
    };
  };

  let compare = (a, b) =>
    switch (a.major - b.major) {
    | 0 =>
      switch (a.minor - b.minor) {
      | 0 =>
        switch (a.patch - b.patch) {
        | 0 =>
          switch (comparePrerelease(a.prerelease, b.prerelease)) {
          | 0 => compareBuild(a.build, b.build)
          | v => v
          }
        | v => v
        }
      | v => v
      }
    | v => v
    };

  let%test_module "compare" =
    (module
     {
       let ppOp =
         fun
         | 0 => "="
         | n when n > 0 => ">"
         | _ => "<";

       let expectComparesAs = (a, b, e) => {
         let a = parseExn(a);
         let b = parseExn(b);
         let c1 = compare(a, b);
         let c2 = compare(b, a);
         if (c1 == e && c2 == - e) {
           true;
         } else {
           Format.printf(
             "@[<v 2>Failed to compare:@\nexpected: %a %s %a@\n     got: %a %s %a@]@\n",
             pp,
             a,
             ppOp(e),
             pp,
             b,
             pp,
             a,
             ppOp(c1),
             pp,
             b,
           );
           false;
         };
       };

       let cases = [
         ("1.0.0", "2.0.0", (-1)),
         ("2.0.0", "1.0.0", 1),
         ("1.0.0", "1.0.0", 0),
         ("1.1.0", "1.0.0", 1),
         ("1.0.0", "1.1.0", (-1)),
         ("1.1.0", "1.1.0", 0),
         ("1.1.1", "1.1.0", 1),
         ("1.1.0", "1.1.1", (-1)),
         ("1.1.1", "1.1.1", 0),
         ("1.1.1-alpha", "1.1.1", (-1)),
         ("1.1.1", "1.1.1-alpha", 1),
         ("1.1.1-alpha", "1.1.1-alpha", 0),
         ("1.1.1-alpha.1", "1.1.1-alpha", 1),
         ("1.1.1-alpha", "1.1.1-alpha.1", (-1)),
         ("1.1.1-alpha.1", "1.1.1-alpha.1", 0),
         ("1.1.1-alpha.2", "1.1.1-alpha.1", 1),
         ("1.1.1-alpha.1", "1.1.1-alpha.2", (-1)),
         ("1.1.1-alpha.1", "1.1.1-alpha.a", (-1)),
         ("1.1.1-alpha.a", "1.1.1-alpha.1", 1),
         ("1.1.1-alpha", "1.1.1-alpha.a", (-1)),
         ("1.1.1-alpha.a", "1.1.1-alpha", 1),
         ("1.1.1-alpha", "1.1.1-beta", (-1)),
         ("1.1.1-beta", "1.1.1-alpha", 1),
         ("1.1.1-alpha+1", "1.1.1-alpha+1", 0),
         ("1.1.1-alpha+2", "1.1.1-alpha+1", 1),
         ("1.1.1-alpha+1", "1.1.1-alpha+2", (-1)),
         ("1.1.1", "1.1.1+1", 1),
         ("1.1.1+1", "1.1.1", (-1)),
         ("1.1.1+1", "1.1.1+1", 0),
         ("1.1.1+2", "1.1.1+1", 1),
         ("1.1.1+1", "1.1.1+2", (-1)),
         ("1.1.1+1.2", "1.1.1+1", 1),
         ("1.1.1+1", "1.1.1+1.2", (-1)),
       ];

       let%test "comparing" = {
         let f = (passes, (a, b, e)) => passes && expectComparesAs(a, b, e);

         List.fold_left(~f, ~init=true, cases);
       };
     });

  let of_yojson = json =>
    switch (json) {
    | `String(v) => parse(v)
    | _ => Error("expected string")
    };

  let to_yojson = v => `String(show(v));
};

module Constraint = VersionBase.Constraint.Make(Version);

module Formula = {
  include VersionBase.Formula.Make(Version, Constraint);

  let any: DNF.t = ([[Constraint.ANY]]: DNF.t);

  module Parser = {
    let sliceToEnd = (text, num) =>
      String.sub(text, num, String.length(text) - num);

    let isint = v =>
      try(
        {
          ignore(int_of_string(v));
          true;
        }
      ) {
      | _ => false
      };

    let parsePrerelaseAndBuild = v =>
      switch (Version.parsePrerelaseAndBuild(v)) {
      | Ok(v) => v
      | Error(err) => failwith(err)
      };

    let exactPartial = partial =>
      switch (partial) {
      | `AllStar => failwith("* cannot be compared")
      | `MajorStar(major) => Version.make(major, 0, 0)
      | `MinorStar(major, minor) => Version.make(major, minor, 0)
      | `Major(major, prerelease, build) =>
        Version.make(~prerelease, ~build, major, 0, 0)
      | `Minor(major, minor, prerelease, build) =>
        Version.make(~prerelease, ~build, major, minor, 0)
      | `Patch(major, minor, patch, prerelease, build) =>
        Version.make(~prerelease, ~build, major, minor, patch)
      | `Raw(prerelease, build) => Version.make(~prerelease, ~build, 0, 0, 0)
      };

    let parsePartial = version => {
      let version = version.[0] == '=' ? sliceToEnd(version, 1) : version;

      let version = version.[0] == 'v' ? sliceToEnd(version, 1) : version;

      let parts = String.split_on_char('.', version);
      switch (parts) {
      | ["*" | "x" | "X", ..._rest] => `AllStar
      | [major, "*" | "x" | "X", ..._rest] when isint(major) =>
        `MajorStar(int_of_string(major))
      | [major, minor, "*" | "x" | "X", ..._rest]
          when isint(major) && isint(minor) =>
        `MinorStar((int_of_string(major), int_of_string(minor)))

      | _ =>
        let rx =
          Str.regexp(
            {|^ *\([0-9]+\)\(\.\([0-9]+\)\(\.\([0-9]+\)\)?\)?\(\([-+~][a-z0-9\.]+\)\)?|},
          );
        switch (Str.search_forward(rx, version, 0)) {
        | exception Not_found => `Raw(parsePrerelaseAndBuild(version))
        | _ =>
          let major = int_of_string(Str.matched_group(1, version));
          let (prerelease, build) =
            switch (Str.matched_group(7, version)) {
            | exception Not_found =>
              let last = Str.match_end();
              if (last < String.length(version)) {
                parsePrerelaseAndBuild(sliceToEnd(version, last));
              } else {
                ([], []);
              };
            | text => parsePrerelaseAndBuild(text)
            };
          switch (Str.matched_group(3, version)) {
          | exception Not_found => `Major((major, prerelease, build))
          | minor =>
            let minor = int_of_string(minor);
            switch (Str.matched_group(5, version)) {
            | exception Not_found => `Minor((major, minor, prerelease, build))
            | patch =>
              `Patch((major, minor, int_of_string(patch), prerelease, build))
            };
          };
        };
      };
    };

    let parsePrimitive = item =>
      switch (item.[0]) {
      | '=' =>
        Constraint.EQ(exactPartial(parsePartial(sliceToEnd(item, 1))))
      | '>' =>
        switch (item.[1]) {
        | '=' =>
          Constraint.GTE(exactPartial(parsePartial(sliceToEnd(item, 2))))
        | _ =>
          Constraint.GT(exactPartial(parsePartial(sliceToEnd(item, 1))))
        }
      | '<' =>
        switch (item.[1]) {
        | '=' =>
          Constraint.LTE(exactPartial(parsePartial(sliceToEnd(item, 2))))
        | _ =>
          Constraint.LT(exactPartial(parsePartial(sliceToEnd(item, 1))))
        }
      | _ =>
        let msg = Printf.sprintf("bad version: %s", item);
        failwith(msg);
      };

    let parseSimple = item =>
      switch (item.[0]) {
      | '~' =>
        switch (parsePartial(sliceToEnd(item, 1))) {
        | `Major(m, prerelease, build) => [
            Constraint.GTE(Version.make(~prerelease, ~build, m, 0, 0)),
            Constraint.LT(Version.make(m + 1, 0, 0)),
          ]
        | `Minor(m, i, prerelease, build) => [
            Constraint.GTE(Version.make(~prerelease, ~build, m, i, 0)),
            Constraint.LT(Version.make(m, i + 1, 0)),
          ]
        | `Patch(m, i, p, prerelease, build) => [
            Constraint.GTE(Version.make(~prerelease, ~build, m, i, p)),
            Constraint.LT(Version.make(m, i + 1, 0)),
          ]
        | `AllStar => failwith("* cannot be tilded")
        | `MajorStar(m) => [
            Constraint.GTE(Version.make(m, 0, 0)),
            Constraint.LT(Version.make(m + 1, 0, 0)),
          ]
        | `MinorStar(m, i) => [
            Constraint.GTE(Version.make(m, i, 0)),
            Constraint.LT(Version.make(m, i + 1, 0)),
          ]
        | `Raw(_) => failwith("Bad tilde")
        }

      | '^' =>
        switch (parsePartial(sliceToEnd(item, 1))) {
        | `Major(m, prerelease, build) => [
            GTE(Version.make(~prerelease, ~build, m, 0, 0)),
            LT(Version.make(m + 1, 0, 0)),
          ]
        | `Minor(0, i, prerelease, build) => [
            GTE(Version.make(~prerelease, ~build, 0, i, 0)),
            LT(Version.make(0, i + 1, 0)),
          ]
        | `Minor(m, i, prerelease, build) => [
            GTE(Version.make(~prerelease, ~build, m, i, 0)),
            LT(Version.make(m + 1, 0, 0)),
          ]
        | `Patch(0, 0, p, prerelease, build) => [
            GTE(Version.make(~prerelease, ~build, 0, 0, p)),
            LT(Version.make(0, 0, p + 1)),
          ]
        | `Patch(0, i, p, prerelease, build) => [
            GTE(Version.make(~prerelease, ~build, 0, i, p)),
            LT(Version.make(0, i + 1, 0)),
          ]
        | `Patch(m, i, p, prerelease, build) => [
            GTE(Version.make(~prerelease, ~build, m, i, p)),
            LT(Version.make(m + 1, 0, 0)),
          ]
        | `AllStar => failwith("* cannot be careted")
        | `MajorStar(m) => [
            GTE(Version.make(m, 0, 0)),
            LT(Version.make(m + 1, 0, 0)),
          ]
        | `MinorStar(m, i) => [
            GTE(Version.make(m, i, 0)),
            LT(Version.make(m + 1, i, 0)),
          ]
        | `Raw(_) => failwith("Bad tilde")
        }

      | '>'
      | '<'
      | '=' => [parsePrimitive(item)]

      | _ =>
        switch (parsePartial(item)) {
        | `AllStar => [ANY]
        | `Major(m, [], [])
        | `MajorStar(m) => [
            GTE(Version.make(m, 0, 0)),
            LT(Version.make(m + 1, 0, 0)),
          ]
        | `Major(m, prerelease, build) => [
            EQ(Version.make(~prerelease, ~build, m, 0, 0)),
          ]
        | `Minor(m, i, [], [])
        | `MinorStar(m, i) => [
            GTE(Version.make(m, i, 0)),
            LT(Version.make(m, i + 1, 0)),
          ]
        | `Minor(m, i, prerelease, build) => [
            EQ(Version.make(~prerelease, ~build, m, i, 0)),
          ]
        | `Patch(m, i, p, prerelease, build) => [
            EQ(Version.make(~prerelease, ~build, m, i, p)),
          ]
        | `Raw(_prerelease, _build) => failwith("bad version")
        }
      };

    let parseConj = v => {
      let vs = Str.split(Str.regexp(" +"), v);
      let vs = {
        let f = (vs, v) => vs @ parseSimple(v);
        List.fold_left(~f, ~init=[], vs);
      };

      vs;
    };

    let parseNpmRange = v => {
      let v =
        v
        |> Str.global_replace(Str.regexp(">= +"), ">=")
        |> Str.global_replace(Str.regexp("<= +"), "<=")
        |> Str.global_replace(Str.regexp("> +"), ">")
        |> Str.global_replace(Str.regexp("< +"), "<")
        |> Str.global_replace(Str.regexp("= +"), "=")
        |> Str.global_replace(Str.regexp("~ +"), "~")
        |> Str.global_replace(Str.regexp("^ +"), "^");

      let vs = Str.split(Str.regexp(" +- +"), v);
      switch (vs) {
      | [item] => parseConj(item)
      | [left, right] =>
        let left = Constraint.GTE(parsePartial(left) |> exactPartial);
        let right =
          switch (parsePartial(right)) {
          | `AllStar => Constraint.ANY
          | `Major(m, _, _)
          | `MajorStar(m) => Constraint.LT(Version.make(m + 1, 0, 0))
          | `Minor(m, i, _, _)
          | `MinorStar(m, i) => Constraint.LT(Version.make(m, i + 1, 0))
          | `Patch(m, i, p, prerelease, build) =>
            Constraint.LTE(Version.make(~prerelease, ~build, m, i, p))
          | `Raw(prerelease, build) =>
            Constraint.LT(Version.make(~prerelease, ~build, 0, 0, 0))
          };

        [left, right];
      | _ =>
        let msg = Printf.sprintf("invalid version: %s", v);
        failwith(msg);
      };
    };

    let parse = ParseUtils.disjunction(~parse=parseNpmRange);
  };

  let parse = formula =>
    try(Ok(Parser.parse(formula))) {
    | Failure(message) =>
      Error("Failed with message: " ++ message ++ " : " ++ formula)
    | e =>
      Error(
        "Invalid formula (pretending its any): "
        ++ formula
        ++ " "
        ++ Printexc.to_string(e),
      )
    };

  let parseExn = formula =>
    switch (parse(formula)) {
    | Ok(f) => f
    | Error(err) => raise(Invalid_argument(err))
    };

  let parserDnf = {
    let p = parse;
    open P;
    let* input = take_while1(_ => true);
    switch (p(input)) {
    | Ok(v) => return(v)
    | Error(msg) => fail(msg)
    };
  };
  let%test_module "parse" =
    (module
     {
       let expectParsesTo = (v, e) => {
         let p = parse(v);
         switch (e, p) {
         | (Error(_), Error(_)) => true
         | (Ok(e), Ok(p)) =>
           if (DNF.compare(p, e) == 0) {
             true;
           } else {
             Format.printf(
               "@[<v 2>Failed to parse: %s@\nexpected: %a@\n     got: %a@]@\n",
               v,
               DNF.pp,
               e,
               DNF.pp,
               p,
             );
             false;
           }
         | (Error(_), Ok(p)) =>
           Format.printf(
             "@[<v 2>Expected to error but it parses: %s@\nas: %a@]@\n",
             v,
             DNF.pp,
             p,
           );
           false;
         | (Ok(e), Error(err)) =>
           Format.printf(
             "@[<v 2>Expected to parse but it errors: %s@\nexpected: %a@\nerror: %s@]@\n",
             v,
             DNF.pp,
             e,
             err,
           );
           false;
         };
       };

       let cases =
         Constraint.(
           Version.[
             ("", Ok([[ANY]])),
             (" ", Ok([[ANY]])),
             ("  ", Ok([[ANY]])),
             ("*", Ok([[ANY]])),
             ("* ", Ok([[ANY]])),
             (" *", Ok([[ANY]])),
             (" * ", Ok([[ANY]])),
             ("1.x", Ok([[GTE(make(1, 0, 0)), LT(make(2, 0, 0))]])),
             ("1.x.x", Ok([[GTE(make(1, 0, 0)), LT(make(2, 0, 0))]])),
             ("1.1.x", Ok([[GTE(make(1, 1, 0)), LT(make(1, 2, 0))]])),
             ("1", Ok([[GTE(make(1, 0, 0)), LT(make(2, 0, 0))]])),
             ("1.1", Ok([[GTE(make(1, 1, 0)), LT(make(1, 2, 0))]])),
             ("1.1.1", Ok([[EQ(Version.(make(1, 1, 1)))]])),
             ("=1.1.1", Ok([[EQ(Version.(make(1, 1, 1)))]])),
             (">1", Ok([[GT(Version.(make(1, 0, 0)))]])),
             (">1.1", Ok([[GT(Version.(make(1, 1, 0)))]])),
             (">1.1.1", Ok([[GT(Version.(make(1, 1, 1)))]])),
             (">1.x", Ok([[GT(Version.(make(1, 0, 0)))]])),
             (">1.x.x", Ok([[GT(Version.(make(1, 0, 0)))]])),
             (">1.1.x", Ok([[GT(Version.(make(1, 1, 0)))]])),
             ("<1.x", Ok([[LT(Version.(make(1, 0, 0)))]])),
             ("<1.x.x", Ok([[LT(Version.(make(1, 0, 0)))]])),
             ("<1.1.x", Ok([[LT(Version.(make(1, 1, 0)))]])),
             ("<1", Ok([[LT(Version.(make(1, 0, 0)))]])),
             ("<1.1", Ok([[LT(Version.(make(1, 1, 0)))]])),
             ("<1.1.1", Ok([[LT(Version.(make(1, 1, 1)))]])),
             (">=1.x", Ok([[GTE(Version.(make(1, 0, 0)))]])),
             (">=1.x.x", Ok([[GTE(Version.(make(1, 0, 0)))]])),
             (">=1.1.x", Ok([[GTE(Version.(make(1, 1, 0)))]])),
             (">=1", Ok([[GTE(Version.(make(1, 0, 0)))]])),
             (">=1.1", Ok([[GTE(Version.(make(1, 1, 0)))]])),
             (">=1.1.1", Ok([[GTE(Version.(make(1, 1, 1)))]])),
             ("<=1.x", Ok([[LTE(Version.(make(1, 0, 0)))]])),
             ("<=1.x.x", Ok([[LTE(Version.(make(1, 0, 0)))]])),
             ("<=1.1.x", Ok([[LTE(Version.(make(1, 1, 0)))]])),
             ("<=1", Ok([[LTE(Version.(make(1, 0, 0)))]])),
             ("<=1.1", Ok([[LTE(Version.(make(1, 1, 0)))]])),
             ("<=1.1.1", Ok([[LTE(Version.(make(1, 1, 1)))]])),
             (
               ">=1.1.1-alpha",
               Ok([
                 [GTE(Version.(make(~prerelease=[W("alpha")], 1, 1, 1)))],
               ]),
             ),
             (
               ">1.1.1-alpha",
               Ok([
                 [GT(Version.(make(~prerelease=[W("alpha")], 1, 1, 1)))],
               ]),
             ),
             (
               "<=1.1.1-alpha",
               Ok([
                 [LTE(Version.(make(~prerelease=[W("alpha")], 1, 1, 1)))],
               ]),
             ),
             (
               "<1.1.1-alpha",
               Ok([
                 [LT(Version.(make(~prerelease=[W("alpha")], 1, 1, 1)))],
               ]),
             ),
             (
               "1-alpha",
               Ok([
                 [EQ(Version.(make(~prerelease=[W("alpha")], 1, 0, 0)))],
               ]),
             ),
             (
               "1.1-alpha",
               Ok([
                 [EQ(Version.(make(~prerelease=[W("alpha")], 1, 1, 0)))],
               ]),
             ),
             ("alpha", Error("err")),
             ("> 1", Ok([[GT(Version.(make(1, 0, 0)))]])),
             ("> 1.1", Ok([[GT(Version.(make(1, 1, 0)))]])),
             ("> 1.1.1", Ok([[GT(Version.(make(1, 1, 1)))]])),
             (">= 1", Ok([[GTE(Version.(make(1, 0, 0)))]])),
             (">= 1.1", Ok([[GTE(Version.(make(1, 1, 0)))]])),
             (">= 1.1.1", Ok([[GTE(Version.(make(1, 1, 1)))]])),
             ("< 1", Ok([[LT(Version.(make(1, 0, 0)))]])),
             ("< 1.1", Ok([[LT(Version.(make(1, 1, 0)))]])),
             ("< 1.1.1", Ok([[LT(Version.(make(1, 1, 1)))]])),
             ("<= 1", Ok([[LTE(Version.(make(1, 0, 0)))]])),
             ("<= 1.1", Ok([[LTE(Version.(make(1, 1, 0)))]])),
             ("<= 1.1.1", Ok([[LTE(Version.(make(1, 1, 1)))]])),
             (" > 1", Ok([[GT(Version.(make(1, 0, 0)))]])),
             (" > 1.1", Ok([[GT(Version.(make(1, 1, 0)))]])),
             (" > 1.1.1", Ok([[GT(Version.(make(1, 1, 1)))]])),
             (" >= 1", Ok([[GTE(Version.(make(1, 0, 0)))]])),
             (" >= 1.1", Ok([[GTE(Version.(make(1, 1, 0)))]])),
             (" >= 1.1.1", Ok([[GTE(Version.(make(1, 1, 1)))]])),
             (" < 1", Ok([[LT(Version.(make(1, 0, 0)))]])),
             (" < 1.1", Ok([[LT(Version.(make(1, 1, 0)))]])),
             (" < 1.1.1", Ok([[LT(Version.(make(1, 1, 1)))]])),
             (" <= 1", Ok([[LTE(Version.(make(1, 0, 0)))]])),
             (" <= 1.1", Ok([[LTE(Version.(make(1, 1, 0)))]])),
             (" <= 1.1.1", Ok([[LTE(Version.(make(1, 1, 1)))]])),
             (
               "1.1.1 || 2.2.2",
               Ok([
                 [EQ(Version.(make(1, 1, 1)))],
                 [EQ(Version.(make(2, 2, 2)))],
               ]),
             ),
             (
               "1 || 2.2.2",
               Ok([
                 [
                   GTE(Version.(make(1, 0, 0))),
                   LT(Version.(make(2, 0, 0))),
                 ],
                 [EQ(Version.(make(2, 2, 2)))],
               ]),
             ),
             (
               "1 || 2",
               Ok([
                 [
                   GTE(Version.(make(1, 0, 0))),
                   LT(Version.(make(2, 0, 0))),
                 ],
                 [
                   GTE(Version.(make(2, 0, 0))),
                   LT(Version.(make(3, 0, 0))),
                 ],
               ]),
             ),
             (
               "1 || 2 || 3",
               Ok([
                 [
                   GTE(Version.(make(1, 0, 0))),
                   LT(Version.(make(2, 0, 0))),
                 ],
                 [
                   GTE(Version.(make(2, 0, 0))),
                   LT(Version.(make(3, 0, 0))),
                 ],
                 [
                   GTE(Version.(make(3, 0, 0))),
                   LT(Version.(make(4, 0, 0))),
                 ],
               ]),
             ),
             (
               ">1.1.1 || <2.2.2",
               Ok([
                 [GT(Version.(make(1, 1, 1)))],
                 [LT(Version.(make(2, 2, 2)))],
               ]),
             ),
             (
               ">1.1.1 <2.2.2",
               Ok([
                 [
                   GT(Version.(make(1, 1, 1))),
                   LT(Version.(make(2, 2, 2))),
                 ],
               ]),
             ),
             (
               ">1.1.1  <2.2.2",
               Ok([
                 [
                   GT(Version.(make(1, 1, 1))),
                   LT(Version.(make(2, 2, 2))),
                 ],
               ]),
             ),
             (
               ">1  <2.2.2",
               Ok([
                 [
                   GT(Version.(make(1, 0, 0))),
                   LT(Version.(make(2, 2, 2))),
                 ],
               ]),
             ),
             (
               "> 1  <2 <3",
               Ok([
                 [
                   GT(Version.(make(1, 0, 0))),
                   LT(Version.(make(2, 0, 0))),
                   LT(Version.(make(3, 0, 0))),
                 ],
               ]),
             ),
           ]
         );

       let%test "parsing" = {
         let f = (passes, (v, e)) => passes && expectParsesTo(v, e);

         List.fold_left(~f, ~init=true, cases);
       };
     });

  let%test_module "matches" =
    (module
     {
       let expectMatches = (m, v, f) => {
         let pf = parseExn(f);
         let pv = Version.parseExn(v);
         if (m == DNF.matches(~version=pv, pf)) {
           true;
         } else {
           let m = if (m) {"TO MATCH"} else {"NOT TO MATCH"};
           Format.printf("Expected %s %s %s\n", v, m, f);
           false;
         };
       };

       let cases = [
         (true, "1.0.0", "1.0.0"),
         (false, "1.0.1", "1.0.0"),
         (true, "1.0.0", ">=1.0.0"),
         (true, "1.0.0", "<=1.0.0"),
         (true, "0.9.0", "<=1.0.0"),
         (true, "0.9.0", "<1.0.0"),
         (false, "1.1.0", "<=1.0.0"),
         (false, "1.1.0", "<1.0.0"),
         (true, "1.1.0", ">=1.0.0"),
         (true, "1.1.0", ">1.0.0"),
         (false, "0.9.0", ">=1.0.0"),
         (false, "1.0.0", ">1.0.0"),
         (true, "1.0.0", "1.0.0 - 1.1.0"),
         (true, "1.1.0", "1.0.0 - 1.1.0"),
         (false, "0.9.0", "1.0.0 - 1.1.0"),
         (false, "1.2.0", "1.0.0 - 1.1.0"),
         /* tilda */
         (true, "1.0.0", "~1.0.0"),
         (false, "2.0.0", "~1.0.0"),
         (false, "0.9.0", "~1.0.0"),
         (false, "1.1.0", "~1.0.0"),
         (true, "1.0.1", "~1.0.0"),
         (true, "0.3.0", "~0.3.0"),
         (false, "0.4.0", "~0.3.0"),
         (false, "0.2.0", "~0.3.0"),
         (true, "0.3.1", "~0.3.0"),
         /* caret */
         (true, "1.0.0", "^1.0.0"),
         (false, "2.0.0", "^1.0.0"),
         (false, "0.9.0", "^1.0.0"),
         (true, "1.1.0", "^1.0.0"),
         (true, "1.0.1", "^1.0.0"),
         (true, "0.3.0", "^0.3.0"),
         (false, "0.4.0", "^0.3.0"),
         (false, "0.2.0", "^0.3.0"),
         (true, "0.3.1", "^0.3.0"),
         /* prereleases */
         (true, "1.0.0-alpha", "1.0.0-alpha"),
         (false, "1.0.0-alpha", ">1.0.0"),
         (false, "1.0.0-alpha", ">=1.0.0"),
         (false, "1.0.0-alpha", "<1.0.0"),
         (false, "1.0.0-alpha", "<=1.0.0"),
         (true, "1.0.0-alpha", ">=1.0.0-alpha"),
         (true, "1.0.0-alpha", ">=1.0.0-alpha < 2.0.0"),
         (true, "1.0.0-alpha.2", ">1.0.0-alpha.1 < 2.0.0"),
         (true, "1.0.0-alpha", ">0.1.0 <=1.0.0-alpha"),
         (true, "1.0.0-alpha.1", ">0.1.0 <1.0.0-alpha.2"),
         (true, "1.0.0-alpha", "<=1.0.0-alpha"),
         (true, "1.0.0-alpha.2", ">=1.0.0-alpha.1"),
         (true, "1.0.0-alpha.2", ">1.0.0-alpha.1"),
         (true, "1.0.0-alpha.1", "<=1.0.0-alpha.2"),
         (true, "1.0.0-alpha.1", "<1.0.0-alpha.2"),
         (false, "2.0.0-alpha", ">=1.0.0 < 3.0.0"),
       ];

       let%test "parsing" = {
         let f = (passes, (m, v, f)) => expectMatches(m, v, f) && passes;

         List.fold_left(~f, ~init=true, cases);
       };
     });
};

let caretRangeOfVersion = (version: Version.t) => {
  let upperBound =
    if (version.major < 1) {
      Version.{
        major: 0,
        minor: version.minor + 1,
        patch: 0,
        prerelease: [],
        build: [],
      };
    } else {
      Version.{
        major: version.major + 1,
        minor: 0,
        patch: 0,
        prerelease: [],
        build: [],
      };
    };

  [[Constraint.GTE(version), Constraint.LT(upperBound)]];
};
