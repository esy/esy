module String = Astring.String;
module P = Parse;

/** opam versions are Debian-style versions */
module Version = {
  type t = OpamPackage.Version.t;

  let compare = OpamPackage.Version.compare;
  let show = OpamPackage.Version.to_string;
  let pp = (fmt, v) => Fmt.pf(fmt, "opam:%s", show(v));
  let parse = v => Ok(OpamPackage.Version.of_string(v));
  let parser = {
    open Parse;
    let* input = take_while1(_ => true);
    try(return(OpamPackage.Version.of_string(input))) {
    | _ => fail("cannot parse opam version")
    };
  };
  let parseExn = v => OpamPackage.Version.of_string(v);
  let majorMinorPatch = _v => None;
  let prerelease = _v => false;
  let stripPrerelease = v => v;
  let to_yojson = v => `String(show(v));
  let of_yojson =
    fun
    | `String(v) => parse(v)
    | _ => Error("expected a string");

  let ofSemver = v => {
    let v = SemverVersion.Version.show(v);
    parse(v);
  };

  let sexp_of_t = v => Sexplib0.Sexp.(List([Atom("Opam"), Atom(show(v))]));
};

let caretRange = v =>
  switch (SemverVersion.Version.parse(v)) {
  | Ok(v) =>
    open Result.Syntax;
    let ve =
      if (v.major == 0) {
        {...v, minor: v.minor + 1};
      } else {
        {...v, major: v.major + 1};
      };

    let* v = Version.ofSemver(v);
    let* ve = Version.ofSemver(ve);
    [@implicit_arity] Ok(v, ve);
  | Error(_) => Error("^ cannot be applied to: " ++ v)
  };

let tildaRange = v =>
  switch (SemverVersion.Version.parse(v)) {
  | Ok(v) =>
    open Result.Syntax;
    let ve = {...v, minor: v.minor + 1};
    let* v = Version.ofSemver(v);
    let* ve = Version.ofSemver(ve);
    [@implicit_arity] Ok(v, ve);
  | Error(_) => Error("~ cannot be applied to: " ++ v)
  };

module Constraint = VersionBase.Constraint.Make(Version);

/**
 * Npm formulas over opam versions.
 */
module Formula = {
  include VersionBase.Formula.Make(Version, Constraint);

  let any: DNF.t = ([[Constraint.ANY]]: DNF.t);

  module C = Constraint;

  let parseRel = text => {
    module String = Astring.String;
    Result.Syntax.(
      switch (String.trim(text)) {
      | "*"
      | "" => return([C.ANY])
      | text =>
        let len = String.length(text);
        let fst =
          if (len > 0) {
            Some(text.[0]);
          } else {
            None;
          };
        let snd =
          if (len > 1) {
            Some(text.[1]);
          } else {
            None;
          };
        switch (fst, snd) {
        | (Some('^'), _) =>
          let v = String.Sub.(text |> v(~start=1) |> to_string);
          let* (v, ve) = caretRange(v);
          return([C.GTE(v), C.LT(ve)]);
        | (Some('~'), _) =>
          let v = String.Sub.(text |> v(~start=1) |> to_string);
          let* (v, ve) = tildaRange(v);
          return([C.GTE(v), C.LT(ve)]);
        | (Some('='), _) =>
          let text = String.Sub.(text |> v(~start=1) |> to_string);
          let* v = Version.parse(text);
          return([C.EQ(v)]);
        | (Some('<'), Some('=')) =>
          let text = String.Sub.(text |> v(~start=2) |> to_string);
          let* v = Version.parse(text);
          return([C.LTE(v)]);
        | (Some('<'), _) =>
          let text = String.Sub.(text |> v(~start=1) |> to_string);
          let* v = Version.parse(text);
          return([C.LT(v)]);
        | (Some('>'), Some('=')) =>
          let text = String.Sub.(text |> v(~start=2) |> to_string);
          let* v = Version.parse(text);
          return([C.GTE(v)]);
        | (Some('>'), _) =>
          let text = String.Sub.(text |> v(~start=1) |> to_string);
          let* v = Version.parse(text);
          return([C.GT(v)]);
        | (_, _) =>
          let* v = Version.parse(text);
          return([C.EQ(v)]);
        };
      }
    );
  };

  let parseExn = v => {
    let parseSimple = v => {
      let parse = v => {
        let v = String.trim(v);
        if (v == "") {
          [C.ANY];
        } else {
          switch (parseRel(v)) {
          | Ok(v) => v
          | Error(err) => failwith("Error: " ++ err)
          };
        };
      };

      let conjs = ParseUtils.conjunction(~parse, v);
      let conjs = {
        let f = (conjs, c) => conjs @ c;
        List.fold_left(~init=[], ~f, conjs);
      };

      let conjs =
        switch (conjs) {
        | [] => [C.ANY]
        | conjs => conjs
        };
      conjs;
    };

    ParseUtils.disjunction(~parse=parseSimple, v);
  };

  let parse = v =>
    try(Ok(parseExn(v))) {
    | _ =>
      let msg = "unable to parse formula: " ++ v;
      Error(msg);
    };

  let parserDnf = {
    open P;
    let* input = take_while1(_ => true);
    return(parseExn(input));
  };

  let%test_module "parse" =
    (module
     {
       let v = Version.parseExn;

       let parsesOk = (f, e) => {
         let pf = parseExn(f);
         if (pf != e) {
           failwith("Received: " ++ DNF.show(pf));
         } else {
           ();
         };
       };

       let%test_unit _ = parsesOk(">=1.7.0", [[C.GTE(v("1.7.0"))]]);
       let%test_unit _ = parsesOk("*", [[C.ANY]]);
       let%test_unit _ = parsesOk("", [[C.ANY]]);
     });

  let%test_module "matches" =
    (module
     {
       let v = Version.parseExn;
       let f = parseExn;

       let%test _ = DNF.matches(~version=v("1.8.0"), f(">=1.7.0"));
       let%test _ = DNF.matches(~version=v("0.3"), f("=0.3"));
       let%test _ = DNF.matches(~version=v("0.3"), f("0.3"));
     });
};
