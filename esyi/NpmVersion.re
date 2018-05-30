[@deriving yojson]
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

  let viewRange = GenericVersion.view(toString);

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
    | `Minor(m, i, q) => Printf.sprintf("Minor %d %d %s", m, i, showOpt(q))
    | `Patch(m, i, p, q) =>
      Printf.sprintf("Minor %d %d %d %s", m, i, p, showOpt(q))
    | `Raw(s) => "Raw " ++ s
    };

  let exactPartial = partial =>
    switch (partial) {
    | `AllStar => failwith("* cannot be compared")
    | `MajorStar(num) => {major: num, minor: 0, patch: 0, release: None}
    | `MinorStar(m, i) => {major: m, minor: i, patch: 0, release: None}
    | `Major(m, q) => {major: m, minor: 0, patch: 0, release: q}
    | `Minor(m, i, q) => {major: m, minor: i, patch: 0, release: q}
    | `Patch(m, i, p, q) => {major: m, minor: i, patch: p, release: q}
    | `Raw(text) => {major: 0, minor: 0, patch: 0, release: Some(text)}
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

  open GenericVersion;

  /* [@test */
  /*   [ */
  /*     (">=2.3.1", AtLeast({major: 2, minor: 3, patch: 1, release: None})), */
  /*     ("<2.4", LessThan({major: 2, minor: 4, patch: 0, release: None})), */
  /*   ] */
  /* ] */
  let parsePrimitive = item =>
    switch (item.[0]) {
    | '=' => Exactly(parsePartial(sliceToEnd(item, 1)) |> exactPartial)
    | '>' =>
      switch (item.[1]) {
      | '=' => AtLeast(parsePartial(sliceToEnd(item, 2)) |> exactPartial)
      | _ => GreaterThan(parsePartial(sliceToEnd(item, 1)) |> exactPartial)
      }
    | '<' =>
      switch (item.[1]) {
      | '=' => AtMost(parsePartial(sliceToEnd(item, 2)) |> exactPartial)
      | _ => LessThan(parsePartial(sliceToEnd(item, 1)) |> exactPartial)
      }
    | _ => failwith("Bad primitive")
    };

  let parseSimple = item =>
    switch (item.[0]) {
    | '~' =>
      switch (parsePartial(sliceToEnd(item, 1))) {
      | `Major(num, q) =>
        And(
          AtLeast({major: num, minor: 0, patch: 0, release: q}),
          LessThan({major: num + 1, minor: 0, patch: 0, release: None}),
        )
      | `Minor(m, i, q) =>
        And(
          AtLeast({major: m, minor: i, patch: 0, release: q}),
          LessThan({major: m, minor: i + 1, patch: 0, release: None}),
        )
      | `Patch(m, i, p, q) =>
        And(
          AtLeast({major: m, minor: i, patch: p, release: q}),
          LessThan({major: m, minor: i + 1, patch: 0, release: None}),
        )
      | `AllStar => failwith("* cannot be tilded")
      | `MajorStar(num) =>
        And(
          AtLeast({major: num, minor: 0, patch: 0, release: None}),
          LessThan({major: num + 1, minor: 0, patch: 0, release: None}),
        )
      | `MinorStar(m, i) =>
        And(
          AtLeast({major: m, minor: i, patch: 0, release: None}),
          LessThan({major: m, minor: i + 1, patch: 0, release: None}),
        )
      | `Raw(_) => failwith("Bad tilde")
      }
    | '^' =>
      switch (parsePartial(sliceToEnd(item, 1))) {
      | `Major(num, q) =>
        And(
          AtLeast({major: num, minor: 0, patch: 0, release: q}),
          LessThan({major: num + 1, minor: 0, patch: 0, release: None}),
        )
      | `Minor(0, i, q) =>
        And(
          AtLeast({major: 0, minor: i, patch: 0, release: q}),
          LessThan({major: 0, minor: i + 1, patch: 0, release: None}),
        )
      | `Minor(m, i, q) =>
        And(
          AtLeast({major: m, minor: i, patch: 0, release: q}),
          LessThan({major: m + 1, minor: 0, patch: 0, release: None}),
        )
      | `Patch(0, 0, p, q) =>
        And(
          AtLeast({major: 0, minor: 0, patch: p, release: q}),
          LessThan({major: 0, minor: 0, patch: p + 1, release: None}),
        )
      | `Patch(0, i, p, q) =>
        And(
          AtLeast({major: 0, minor: i, patch: p, release: q}),
          LessThan({major: 0, minor: i + 1, patch: 0, release: None}),
        )
      | `Patch(m, i, p, q) =>
        And(
          AtLeast({major: m, minor: i, patch: p, release: q}),
          LessThan({major: m + 1, minor: 0, patch: 0, release: None}),
        )
      | `AllStar => failwith("* cannot be careted")
      | `MajorStar(num) =>
        And(
          AtLeast({major: num, minor: 0, patch: 0, release: None}),
          LessThan({major: num + 1, minor: 0, patch: 0, release: None}),
        )
      | `MinorStar(m, i) =>
        And(
          AtLeast({major: m, minor: i, patch: 0, release: None}),
          LessThan({major: m + 1, minor: i, patch: 0, release: None}),
        )
      | `Raw(_) => failwith("Bad tilde")
      }
    | '>'
    | '<'
    | '=' => parsePrimitive(item)
    | _ =>
      switch (parsePartial(item)) {
      | `AllStar => Any
      /* TODO maybe handle the qualifier */
      | `Major(m, Some(x)) =>
        Exactly({major: m, minor: 0, patch: 0, release: Some(x)})
      | `Major(m, None)
      | `MajorStar(m) =>
        And(
          AtLeast({major: m, minor: 0, patch: 0, release: None}),
          LessThan({major: m + 1, minor: 0, patch: 0, release: None}),
        )
      | `Minor(m, i, Some(x)) =>
        Exactly({major: m, minor: i, patch: 0, release: Some(x)})
      | `Minor(m, i, None)
      | `MinorStar(m, i) =>
        And(
          AtLeast({major: m, minor: i, patch: 0, release: None}),
          LessThan({major: m, minor: i + 1, patch: 0, release: None}),
        )
      | `Patch(m, i, p, q) =>
        Exactly({major: m, minor: i, patch: p, release: q})
      | `Raw(text) =>
        Exactly({major: 0, minor: 0, patch: 0, release: Some(text)})
      }
    };

  let parseSimples = (item, parseSimple) => {
    let item =
      item
      |> Str.global_replace(Str.regexp(">= +"), ">=")
      |> Str.global_replace(Str.regexp("<= +"), "<=")
      |> Str.global_replace(Str.regexp("> +"), ">")
      |> Str.global_replace(Str.regexp("< +"), "<");
    let items = String.split_on_char(' ', item);
    let rec loop = items =>
      switch (items) {
      | [item] => parseSimple(item)
      | [item, ...items] => And(parseSimple(item), loop(items))
      | [] => assert(false)
      };
    loop(items);
  };

  /* [@test */
  /*   GenericVersion.[ */
  /*     ("1.2.3", Exactly({major: 1, minor: 2, patch: 3, release: None})), */
  /*     ( */
  /*       "1.2.3-alpha2", */
  /*       Exactly({major: 1, minor: 2, patch: 3, release: Some("-alpha2")}), */
  /*     ), */
  /*     ( */
  /*       "1.2.3 - 2.3.4", */
  /*       And( */
  /*         AtLeast({major: 1, minor: 2, patch: 3, release: None}), */
  /*         AtMost({major: 2, minor: 3, patch: 4, release: None}), */
  /*       ), */
  /*     ), */
  /*     ( */
  /*       "1.2.3 - 2.3", */
  /*       And( */
  /*         AtLeast({major: 1, minor: 2, patch: 3, release: None}), */
  /*         LessThan({major: 2, minor: 4, patch: 0, release: None}), */
  /*       ), */
  /*     ), */
  /*   ] */
  /* ] */
  /* [@test.print (fmt, v) => Format.fprintf(fmt, "%s", viewRange(v))] */
  let parseNpmRange = simple => {
    let items = Str.split(Str.regexp(" +- +"), simple);
    switch (items) {
    | [item] => parseSimples(item, parseSimple)
    | [left, right] =>
      let left = AtLeast(parsePartial(left) |> exactPartial);
      let right =
        switch (parsePartial(right)) {
        | `AllStar => Any
        /* TODO maybe handle the qualifier */
        | `Major(m, _)
        | `MajorStar(m) =>
          LessThan({major: m + 1, minor: 0, patch: 0, release: None})
        | `Minor(m, i, _)
        | `MinorStar(m, i) =>
          LessThan({major: m, minor: i + 1, patch: 0, release: None})
        | `Patch(m, i, p, q) =>
          AtMost({major: m, minor: i, patch: p, release: q})
        | `Raw(text) =>
          LessThan({major: 0, minor: 0, patch: 0, release: Some(text)})
        };
      And(left, right);
    | _ => failwith("Invalid range")
    };
  };

  /* [@test */
  /*   GenericVersion.[ */
  /*     ("1.2.3", Exactly({major: 1, minor: 2, patch: 3, release: None})), */
  /*     ( */
  /*       "1.2.3-alpha2", */
  /*       Exactly({major: 1, minor: 2, patch: 3, release: Some("-alpha2")}), */
  /*     ), */
  /*     ( */
  /*       "1.2.3 - 2.3.4", */
  /*       And( */
  /*         AtLeast({major: 1, minor: 2, patch: 3, release: None}), */
  /*         AtMost({major: 2, minor: 3, patch: 4, release: None}), */
  /*       ), */
  /*     ), */
  /*     ( */
  /*       "1.2.3 - 2.3 || 5.x", */
  /*       Or( */
  /*         And( */
  /*           AtLeast({major: 1, minor: 2, patch: 3, release: None}), */
  /*           LessThan({major: 2, minor: 4, patch: 0, release: None}), */
  /*         ), */
  /*         And( */
  /*           AtLeast({major: 5, minor: 0, patch: 0, release: None}), */
  /*           LessThan({major: 6, minor: 0, patch: 0, release: None}), */
  /*         ), */
  /*       ), */
  /*     ), */
  /*   ] */
  /* ] */
  /* [@test.call parseOrs(parseNpmRange)] */
  /* [@test.print (fmt, v) => Format.fprintf(fmt, "%s", viewRange(v))] */
  let parseOrs = (parseRange, version) =>
    if (version == "") {
      GenericVersion.Any;
    } else {
      let items = Str.split(Str.regexp(" +|| +"), version);
      let rec loop = items =>
        switch (items) {
        | [] => failwith("WAAAT " ++ version)
        | [item] => parseRange(item)
        | [item, ...items] => Or(parseRange(item), loop(items))
        };
      loop(items);
    };

  let parse = parseOrs(parseNpmRange);
};

/*
 * High level handling of npm versions
 */
let viewConcrete = ((m, i, p, r)) =>
  ([m, i, p] |> List.map(string_of_int) |> String.concat("."))
  ++ (
    switch (r) {
    | None => ""
    | Some(a) => a
    }
  );

let viewRange = GenericVersion.view(viewConcrete);

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
/*   GenericVersion.[ */
/*     ("~1.2.3", parseRange(">=1.2.3 <1.3.0")), */
/*     ("~1.2", parseRange(">=1.2.0 <1.3.0")), */
/*     ("~1.2", parseRange("1.2.x")), */
/*     ("~1", parseRange(">=1.0.0 <2.0.0")), */
/*     ("~1", parseRange("1.x")), */
/*     ("~0.2.3", parseRange(">=0.2.3 <0.3.0")), */
/*     ("~0", parseRange("0.x")), */
/*     ("1.2.3", Exactly({major: 1, minor: 2, patch: 3, release: None})), */
/*     ( */
/*       "1.2.3-alpha2", */
/*       Exactly({major: 1, minor: 2, patch: 3, release: Some("-alpha2")}), */
/*     ), */
/*     ( */
/*       "1.2.3 - 2.3.4", */
/*       And( */
/*         AtLeast({major: 1, minor: 2, patch: 3, release: None}), */
/*         AtMost({major: 2, minor: 3, patch: 4, release: None}), */
/*       ), */
/*     ), */
/*   ] */
/* ] */
/* [@test.print (fmt, v) => Format.fprintf(fmt, "%s", viewRange(v))] */
let parseRange = version =>
  try (Parser.parse(version)) {
  | Failure(message) =>
    print_endline("Failed with message: " ++ message ++ " : " ++ version);
    Any;
  | e =>
    print_endline(
      "Invalid version! pretending its any: "
      ++ version
      ++ " "
      ++ Printexc.to_string(e),
    );
    Any;
  };

let isint = v =>
  try (
    {
      ignore(int_of_string(v));
      true;
    }
  ) {
  | _ => false
  };

let getRest = parts => parts == [] ? None : Some(String.concat(".", parts));

let parseConcrete = version => {
  let parts = String.split_on_char('.', version);
  switch (parts) {
  | [major, minor, patch, ...rest]
      when isint(major) && isint(minor) && isint(patch) => {
      major: int_of_string(major),
      minor: int_of_string(minor),
      patch: int_of_string(patch),
      release: getRest(rest),
    }
  | [major, minor, ...rest] when isint(major) && isint(minor) => {
      major: int_of_string(major),
      minor: int_of_string(minor),
      patch: 0,
      release: getRest(rest),
    }
  | [major, ...rest] when isint(major) => {
      major: int_of_string(major),
      minor: 0,
      patch: 0,
      release: getRest(rest),
    }
  | rest => {major: 0, minor: 0, patch: 0, release: getRest(rest)}
  };
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

let matches = GenericVersion.matches(compare);
