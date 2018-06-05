module type VERSION = {
  type t;

  let equal: (t, t) => bool;
  let compare: (t, t) => int;
  let show: t => string;

  let parse: string => result(t, string);
  let toString: t => string;

  let to_yojson: t => Json.t;
  let of_yojson: Json.t => result(t, string);
};

module Make = (Version: VERSION) => {
  [@deriving yojson]
  type t =
    | OR(t, t)
    | AND(t, t)
    | EQ(Version.t)
    | GT(Version.t)
    | GTE(Version.t)
    | LT(Version.t)
    | LTE(Version.t)
    | NONE
    | ANY;

  /* | UntilNextMajor('concrete) | UntilNextMinor('concrete); */
  /** TODO want a way to exclude npm -alpha items when they don't apply */
  let rec matches = (formula, version) =>
    switch (formula) {
    | EQ(a) => Version.compare(a, version) == 0
    | ANY => true
    | NONE => false
    | GT(a) => Version.compare(a, version) < 0
    | GTE(a) => Version.compare(a, version) <= 0
    | LT(a) => Version.compare(a, version) > 0
    | LTE(a) => Version.compare(a, version) >= 0
    | AND(a, b) => matches(a, version) && matches(b, version)
    | OR(a, b) => matches(a, version) || matches(b, version)
    };

  let rec isTooLarge = (formula, version) =>
    switch (formula) {
    | EQ(a) => Version.compare(a, version) < 0
    | ANY => false
    | NONE => false
    | GT(_a) => false
    | GTE(_a) => false
    | LT(a) => Version.compare(a, version) <= 0
    | LTE(a) => Version.compare(a, version) < 0
    | AND(a, b) => isTooLarge(a, version) || isTooLarge(b, version)
    | OR(a, b) => isTooLarge(a, version) && isTooLarge(b, version)
    };

  let rec toString = range =>
    switch (range) {
    | EQ(a) => Version.toString(a)
    | ANY => "*"
    | NONE => "none"
    | GT(a) => "> " ++ Version.toString(a)
    | GTE(a) => ">= " ++ Version.toString(a)
    | LT(a) => "< " ++ Version.toString(a)
    | LTE(a) => "<= " ++ Version.toString(a)
    | AND(a, b) => toString(a) ++ " && " ++ toString(b)
    | OR(a, b) => toString(a) ++ " || " ++ toString(b)
    };

  let rec map = (transform, range) =>
    switch (range) {
    | EQ(a) => EQ(transform(a))
    | ANY => ANY
    | NONE => NONE
    | GT(a) => GT(transform(a))
    | GTE(a) => GTE(transform(a))
    | LT(a) => LT(transform(a))
    | LTE(a) => LTE(transform(a))
    | AND(a, b) => AND(map(transform, a), map(transform, b))
    | OR(a, b) => OR(map(transform, a), map(transform, b))
    };

  module Parse = {
    let conjunction = (parse, item) => {
      let item =
        item
        |> Str.global_replace(Str.regexp(">= +"), ">=")
        |> Str.global_replace(Str.regexp("<= +"), "<=")
        |> Str.global_replace(Str.regexp("> +"), ">")
        |> Str.global_replace(Str.regexp("< +"), "<");
      let items = String.split_on_char(' ', item);
      let rec loop = items =>
        switch (items) {
        | [item] => parse(item)
        | [item, ...items] => AND(parse(item), loop(items))
        | [] => assert(false)
        };
      loop(items);
    };

    /* [@test */
    /*   VersionFormula.[ */
    /*     ("1.2.3", EQ({major: 1, minor: 2, patch: 3, release: None})), */
    /*     ( */
    /*       "1.2.3-alpha2", */
    /*       EQ({major: 1, minor: 2, patch: 3, release: Some("-alpha2")}), */
    /*     ), */
    /*     ( */
    /*       "1.2.3 - 2.3.4", */
    /*       AND( */
    /*         GTE({major: 1, minor: 2, patch: 3, release: None}), */
    /*         LTE({major: 2, minor: 3, patch: 4, release: None}), */
    /*       ), */
    /*     ), */
    /*     ( */
    /*       "1.2.3 - 2.3 || 5.x", */
    /*       OR( */
    /*         AND( */
    /*           GTE({major: 1, minor: 2, patch: 3, release: None}), */
    /*           LT({major: 2, minor: 4, patch: 0, release: None}), */
    /*         ), */
    /*         AND( */
    /*           GTE({major: 5, minor: 0, patch: 0, release: None}), */
    /*           LT({major: 6, minor: 0, patch: 0, release: None}), */
    /*         ), */
    /*       ), */
    /*     ), */
    /*   ] */
    /* ] */
    /* [@test.call parseOrs(parseNpmRange)] */
    /* [@test.print (fmt, v) => Format.fprintf(fmt, "%s", viewRange(v))] */
    let disjunction = (parse, version) =>
      if (version == "") {
        ANY;
      } else {
        let items = Str.split(Str.regexp(" +|| +"), version);
        let rec loop = items =>
          switch (items) {
          | [] => failwith("WAAAT " ++ version)
          | [item] => parse(item)
          | [item, ...items] => OR(parse(item), loop(items))
          };
        loop(items);
      };
  };
};
