module MakeFormula = Version.Formula.Make;

module Version = {
  [@deriving (eq, yojson)]
  type t = {
    major: int,
    minor: int,
    patch: int,
    release: option(string),
  };

  let toString = ({major, minor, patch, release}) =>
    string_of_int(major)
    ++ "."
    ++ string_of_int(minor)
    ++ "."
    ++ string_of_int(patch)
    ++ (
      switch (release) {
      | None => ""
      | Some(a) => a
      }
    );

  let show = toString;

  let isint = v =>
    try (
      {
        ignore(int_of_string(v));
        true;
      }
    ) {
    | _ => false
    };

  let getRest = parts =>
    parts == [] ? None : Some(String.concat(".", parts));

  let parse = version => {
    let parts = String.split_on_char('.', version);
    switch (parts) {
    | [major, minor, patch, ...rest]
        when isint(major) && isint(minor) && isint(patch) =>
      Ok({
        major: int_of_string(major),
        minor: int_of_string(minor),
        patch: int_of_string(patch),
        release: getRest(rest),
      })
    | [major, minor, ...rest] when isint(major) && isint(minor) =>
      Ok({
        major: int_of_string(major),
        minor: int_of_string(minor),
        patch: 0,
        release: getRest(rest),
      })
    | [major, ...rest] when isint(major) =>
      Ok({
        major: int_of_string(major),
        minor: 0,
        patch: 0,
        release: getRest(rest),
      })
    | rest => Ok({major: 0, minor: 0, patch: 0, release: getRest(rest)})
    };
  };

  let parseExn = v =>
    switch (parse(v)) {
    | Ok(v) => v
    | Error(err) => raise(Invalid_argument(err))
    };

  let after = (a, prefix) => {
    let al = String.length(a);
    let pl = String.length(prefix);
    if (al > pl && String.sub(a, 0, pl) == prefix) {
      Some(String.sub(a, pl, al - pl));
    } else {
      None;
    };
  };

  let compareExtra = (a, b) =>
    switch (a, b) {
    | (Some(a), Some(b)) =>
      switch (after(a, "-beta"), after(b, "-beta")) {
      | (Some(a), Some(b)) =>
        try (int_of_string(a) - int_of_string(b)) {
        | _ => compare(a, b)
        }
      | _ =>
        switch (after(a, "-alpha"), after(b, "-alpha")) {
        | (Some(a), Some(b)) =>
          try (int_of_string(a) - int_of_string(b)) {
          | _ => compare(a, b)
          }
        | _ =>
          try (int_of_string(a) - int_of_string(b)) {
          | _ => compare(a, b)
          }
        }
      }
    | _ => compare(a, b)
    };

  let compare =
      (
        {major: ma, minor: ia, patch: pa, release: ra},
        {major: mb, minor: ib, patch: pb, release: rb},
      ) =>
    ma != mb ?
      ma - mb : ia != ib ? ia - ib : pa != pb ? pa - pb : compareExtra(ra, rb);
};

module Formula = {
  include MakeFormula(Version);

  module Parser = {
    /**
 * Do the nitty gritty parsing of npm semver.
 * Follows this spec: https://docs.npmjs.com/misc/semver
 */
    type partial = [
      | `Major(int)
      | `Minor(int, int)
      | `Patch(int, int, int)
      | `Qualified(int, int, int, string)
    ];

    let sliceToEnd = (text, num) =>
      String.sub(text, num, String.length(text) - num);

    let isint = v =>
      try (
        {
          ignore(int_of_string(v));
          true;
        }
      ) {
      | _ => false
      };

    let getRest = parts =>
      parts == [] ? None : Some(String.concat(".", parts));

    let splitRest = value =>
      try (
        switch (String.split_on_char('-', value)) {
        | [_single] =>
          switch (String.split_on_char('+', value)) {
          | [_single] =>
            switch (String.split_on_char('~', value)) {
            | [single] => (int_of_string(single), None)
            | [single, ...rest] => (
                int_of_string(single),
                Some("~" ++ String.concat("~", rest)),
              )
            | _ => (0, Some(value))
            }
          | [single, ...rest] => (
              int_of_string(single),
              Some("+" ++ String.concat("+", rest)),
            )
          | _ => (0, Some(value))
          }
        | [single, ...rest] => (
            int_of_string(single),
            Some("-" ++ String.concat("-", rest)),
          )
        | _ => (0, Some(value))
        }
      ) {
      | _ => (0, Some(value))
      };

    let showOpt = n =>
      switch (n) {
      | None => "None"
      | Some(x) => Printf.sprintf("Some(%s)", x)
      };

    let showPartial = x =>
      switch (x) {
      | `AllStar => "AllStar"
      | `MajorStar(num) => Printf.sprintf("MajorStar %d", num)
      | `MinorStar(m, i) => Printf.sprintf("MinorStar %d %d", m, i)
      | `Major(m, q) => Printf.sprintf("Major %d %s", m, showOpt(q))
      | `Minor(m, i, q) =>
        Printf.sprintf("Minor %d %d %s", m, i, showOpt(q))
      | `Patch(m, i, p, q) =>
        Printf.sprintf("Minor %d %d %d %s", m, i, p, showOpt(q))
      | `Raw(s) => "Raw " ++ s
      };

    let exactPartial = partial =>
      switch (partial) {
      | `AllStar => failwith("* cannot be compared")
      | `MajorStar(num) => {
          Version.major: num,
          minor: 0,
          patch: 0,
          release: None,
        }
      | `MinorStar(m, i) => {
          Version.major: m,
          minor: i,
          patch: 0,
          release: None,
        }
      | `Major(m, q) => {Version.major: m, minor: 0, patch: 0, release: q}
      | `Minor(m, i, q) => {Version.major: m, minor: i, patch: 0, release: q}
      | `Patch(m, i, p, q) => {
          Version.major: m,
          minor: i,
          patch: p,
          release: q,
        }
      | `Raw(text) => {
          Version.major: 0,
          minor: 0,
          patch: 0,
          release: Some(text),
        }
      };

    /* [@test */
    /*   [ */
    /*     ("*", `AllStar), */
    /*     ("2.x", `MajorStar(2)), */
    /*     ("1.3.X", `MinorStar((1, 3))), */
    /*     ("v1.3.*", `MinorStar((1, 3))), */
    /*     ("1", `Major((1, None))), */
    /*     ("1-beta.2", `Major((1, Some("-beta.2")))), */
    /*     ("1.2-beta.2", `Minor((1, 2, Some("-beta.2")))), */
    /*     ("1.4.23-alpha1", `Patch((1, 4, 23, Some("-alpha1")))), */
    /*     ("1.2.3alpha2", `Patch((1, 2, 3, Some("alpha2")))), */
    /*     ("what", `Raw("what")), */
    /*   ] */
    /* ] */
    /* [@test.print (fmt, x) => Format.fprintf(fmt, "%s", showPartial(x))] */
    let parsePartial = version => {
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
            {|^\([0-9]+\)\(\.\([0-9]+\)\(\.\([0-9]+\)\)?\)?\(\([-+~][a-z0-9\.]+\)\)?|},
          );
        switch (Str.search_forward(rx, version, 0)) {
        | exception Not_found => `Raw(version)
        | _ =>
          let major = int_of_string(Str.matched_group(1, version));
          let qual =
            switch (Str.matched_group(7, version)) {
            | exception Not_found =>
              let last = Str.match_end();
              if (last < String.length(version)) {
                Some(sliceToEnd(version, last));
              } else {
                None;
              };
            | text => Some(text)
            };
          switch (Str.matched_group(3, version)) {
          | exception Not_found => `Major((major, qual))
          | minor =>
            let minor = int_of_string(minor);
            switch (Str.matched_group(5, version)) {
            | exception Not_found => `Minor((major, minor, qual))
            | patch => `Patch((major, minor, int_of_string(patch), qual))
            };
          };
        };
      };
    };

    /* [@test */
    /*   [ */
    /*     (">=2.3.1", GTE({major: 2, minor: 3, patch: 1, release: None})), */
    /*     ("<2.4", LT({major: 2, minor: 4, patch: 0, release: None})), */
    /*   ] */
    /* ] */
    let parsePrimitive = item =>
      switch (item.[0]) {
      | '=' => EQ(parsePartial(sliceToEnd(item, 1)) |> exactPartial)
      | '>' =>
        switch (item.[1]) {
        | '=' => GTE(parsePartial(sliceToEnd(item, 2)) |> exactPartial)
        | _ => GT(parsePartial(sliceToEnd(item, 1)) |> exactPartial)
        }
      | '<' =>
        switch (item.[1]) {
        | '=' => LTE(parsePartial(sliceToEnd(item, 2)) |> exactPartial)
        | _ => LT(parsePartial(sliceToEnd(item, 1)) |> exactPartial)
        }
      | _ => failwith("Bad primitive")
      };

    let parseSimple = item =>
      switch (item.[0]) {
      | '~' =>
        switch (parsePartial(sliceToEnd(item, 1))) {
        | `Major(num, q) =>
          AND(
            GTE({major: num, minor: 0, patch: 0, release: q}),
            LT({major: num + 1, minor: 0, patch: 0, release: None}),
          )
        | `Minor(m, i, q) =>
          AND(
            GTE({major: m, minor: i, patch: 0, release: q}),
            LT({major: m, minor: i + 1, patch: 0, release: None}),
          )
        | `Patch(m, i, p, q) =>
          AND(
            GTE({major: m, minor: i, patch: p, release: q}),
            LT({major: m, minor: i + 1, patch: 0, release: None}),
          )
        | `AllStar => failwith("* cannot be tilded")
        | `MajorStar(num) =>
          AND(
            GTE({major: num, minor: 0, patch: 0, release: None}),
            LT({major: num + 1, minor: 0, patch: 0, release: None}),
          )
        | `MinorStar(m, i) =>
          AND(
            GTE({major: m, minor: i, patch: 0, release: None}),
            LT({major: m, minor: i + 1, patch: 0, release: None}),
          )
        | `Raw(_) => failwith("Bad tilde")
        }
      | '^' =>
        switch (parsePartial(sliceToEnd(item, 1))) {
        | `Major(num, q) =>
          AND(
            GTE({major: num, minor: 0, patch: 0, release: q}),
            LT({major: num + 1, minor: 0, patch: 0, release: None}),
          )
        | `Minor(0, i, q) =>
          AND(
            GTE({major: 0, minor: i, patch: 0, release: q}),
            LT({major: 0, minor: i + 1, patch: 0, release: None}),
          )
        | `Minor(m, i, q) =>
          AND(
            GTE({major: m, minor: i, patch: 0, release: q}),
            LT({major: m + 1, minor: 0, patch: 0, release: None}),
          )
        | `Patch(0, 0, p, q) =>
          AND(
            GTE({major: 0, minor: 0, patch: p, release: q}),
            LT({major: 0, minor: 0, patch: p + 1, release: None}),
          )
        | `Patch(0, i, p, q) =>
          AND(
            GTE({major: 0, minor: i, patch: p, release: q}),
            LT({major: 0, minor: i + 1, patch: 0, release: None}),
          )
        | `Patch(m, i, p, q) =>
          AND(
            GTE({major: m, minor: i, patch: p, release: q}),
            LT({major: m + 1, minor: 0, patch: 0, release: None}),
          )
        | `AllStar => failwith("* cannot be careted")
        | `MajorStar(num) =>
          AND(
            GTE({major: num, minor: 0, patch: 0, release: None}),
            LT({major: num + 1, minor: 0, patch: 0, release: None}),
          )
        | `MinorStar(m, i) =>
          AND(
            GTE({major: m, minor: i, patch: 0, release: None}),
            LT({major: m + 1, minor: i, patch: 0, release: None}),
          )
        | `Raw(_) => failwith("Bad tilde")
        }
      | '>'
      | '<'
      | '=' => parsePrimitive(item)
      | _ =>
        switch (parsePartial(item)) {
        | `AllStar => ANY
        /* TODO maybe handle the qualifier */
        | `Major(m, Some(x)) =>
          EQ({major: m, minor: 0, patch: 0, release: Some(x)})
        | `Major(m, None)
        | `MajorStar(m) =>
          AND(
            GTE({major: m, minor: 0, patch: 0, release: None}),
            LT({major: m + 1, minor: 0, patch: 0, release: None}),
          )
        | `Minor(m, i, Some(x)) =>
          EQ({major: m, minor: i, patch: 0, release: Some(x)})
        | `Minor(m, i, None)
        | `MinorStar(m, i) =>
          AND(
            GTE({major: m, minor: i, patch: 0, release: None}),
            LT({major: m, minor: i + 1, patch: 0, release: None}),
          )
        | `Patch(m, i, p, q) =>
          EQ({major: m, minor: i, patch: p, release: q})
        | `Raw(text) =>
          EQ({major: 0, minor: 0, patch: 0, release: Some(text)})
        }
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
    /*       "1.2.3 - 2.3", */
    /*       AND( */
    /*         GTE({major: 1, minor: 2, patch: 3, release: None}), */
    /*         LT({major: 2, minor: 4, patch: 0, release: None}), */
    /*       ), */
    /*     ), */
    /*   ] */
    /* ] */
    /* [@test.print (fmt, v) => Format.fprintf(fmt, "%s", viewRange(v))] */
    let parseNpmRange = simple => {
      let items = Str.split(Str.regexp(" +- +"), simple);
      switch (items) {
      | [item] => Parse.conjunction(parseSimple, item)
      | [left, right] =>
        let left = GTE(parsePartial(left) |> exactPartial);
        let right =
          switch (parsePartial(right)) {
          | `AllStar => ANY
          /* TODO maybe handle the qualifier */
          | `Major(m, _)
          | `MajorStar(m) =>
            LT({major: m + 1, minor: 0, patch: 0, release: None})
          | `Minor(m, i, _)
          | `MinorStar(m, i) =>
            LT({major: m, minor: i + 1, patch: 0, release: None})
          | `Patch(m, i, p, q) =>
            LTE({major: m, minor: i, patch: p, release: q})
          | `Raw(text) =>
            LT({major: 0, minor: 0, patch: 0, release: Some(text)})
          };
        AND(left, right);
      | _ => failwith("Invalid range")
      };
    };

    let parse = Parse.disjunction(parseNpmRange);
  };

  /**
 * Tilde:
 * Allows patch-level changes if a minor version is specified on the comparator.
 * Allows minor-level changes if not.
    ~1.2.3 := >=1.2.3 <1.(2+1).0 := >=1.2.3 <1.3.0
    ~1.2 := >=1.2.0 <1.(2+1).0 := >=1.2.0 <1.3.0 (Same as 1.2.x)
    ~1 := >=1.0.0 <(1+1).0.0 := >=1.0.0 <2.0.0 (Same as 1.x)
    ~0.2.3 := >=0.2.3 <0.(2+1).0 := >=0.2.3 <0.3.0
    ~0.2 := >=0.2.0 <0.(2+1).0 := >=0.2.0 <0.3.0 (Same as 0.2.x)
    ~0 := >=0.0.0 <(0+1).0.0 := >=0.0.0 <1.0.0 (Same as 0.x)
    ~1.2.3-beta.2 := >=1.2.3-beta.2 <1.3.0 Note that prereleases in the 1.2.3 version will be allowed, if they are greater than or equal to beta.2. So, 1.2.3-beta.4 would be allowed, but 1.2.4-beta.2 would not, because it is a prerelease of a different [major, minor, patch] tuple.
*/
  /* [@test */
  /*   VersionFormula.[ */
  /*     ("~1.2.3", parseRange(">=1.2.3 <1.3.0")), */
  /*     ("~1.2", parseRange(">=1.2.0 <1.3.0")), */
  /*     ("~1.2", parseRange("1.2.x")), */
  /*     ("~1", parseRange(">=1.0.0 <2.0.0")), */
  /*     ("~1", parseRange("1.x")), */
  /*     ("~0.2.3", parseRange(">=0.2.3 <0.3.0")), */
  /*     ("~0", parseRange("0.x")), */
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
  /*   ] */
  /* ] */
  /* [@test.print (fmt, v) => Format.fprintf(fmt, "%s", viewRange(v))] */
  let parse = version =>
    try (Parser.parse(version)) {
    | Failure(message) =>
      print_endline("Failed with message: " ++ message ++ " : " ++ version);
      ANY;
    | e =>
      print_endline(
        "Invalid version! pretending its any: "
        ++ version
        ++ " "
        ++ Printexc.to_string(e),
      );
      ANY;
    };
};
