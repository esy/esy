
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

let viewRange = Shared.GenericVersion.view(Shared.Types.viewNpmConcrete);

let sliceToEnd = (text, num) => String.sub(text, num, String.length(text) - num);

let isint = v => try ({ignore(int_of_string(v)); true}) { | _ => false };

let getRest = parts => parts == [] ? None : Some(String.concat(".", parts));

let splitRest = value => {
  try(switch (String.split_on_char('-', value)) {
  | [single] => switch (String.split_on_char('+', value)) {
    | [single] => switch (String.split_on_char('~', value)) {
      | [single] => (int_of_string(single), None)
      | [single, ...rest] => (int_of_string(single), Some("~" ++ String.concat("~", rest)))
      | _ => (0, Some(value))
      }
    | [single, ...rest] => (int_of_string(single), Some("+" ++ String.concat("+", rest)))
    | _ => (0, Some(value))
    }
  | [single, ...rest] => (int_of_string(single), Some("-" ++ String.concat("-", rest)))
  | _ => (0, Some(value))
  }) {
    | _ => (0, Some(value))
  }
};

let showOpt = (n) => switch n { | None => "None" | Some(x) => Printf.sprintf("Some(%s)", x)};

let showPartial = x => switch x {
| `AllStar => "AllStar"
| `MajorStar(num) => Printf.sprintf("MajorStar %d" , num)
| `MinorStar(m, i) => Printf.sprintf("MinorStar %d %d" , m, i)
| `Major(m, q) => Printf.sprintf("Major %d %s" , m, showOpt(q))
| `Minor(m, i, q) => Printf.sprintf("Minor %d %d %s" , m, i, showOpt(q))
| `Patch(m, i, p, q) => Printf.sprintf("Minor %d %d %d %s" , m, i, p, showOpt(q))
| `Raw(s) => "Raw " ++ s
};

let exactPartial = partial => switch partial {
| `AllStar => failwith("* cannot be compared")
| `MajorStar(num) => (num, 0, 0, None)
| `MinorStar(m, i) => (m, i, 0, None)
| `Major(m, q) => (m, 0, 0, q)
| `Minor(m, i, q) => (m, i, 0, q)
| `Patch(m, i, p, q) => (m, i, p, q)
| `Raw(text) => (0, 0, 0, Some(text))
};

[@test [
  ("*", `AllStar),
  ("2.x", `MajorStar(2)),
  ("1.3.X", `MinorStar(1,3)),
  ("v1.3.*", `MinorStar(1,3)),
  ("1", `Major(1, None)),
  ("1-beta.2", `Major(1, Some("-beta.2"))),
  ("1.2-beta.2", `Minor(1, 2, Some("-beta.2"))),
  ("1.4.23-alpha1", `Patch(1, 4, 23, Some("-alpha1"))),
  ("1.2.3alpha2", `Patch(1,2,3, Some("alpha2"))),
  ("what", `Raw("what")),
]]
[@test.print (fmt, x) => Format.fprintf(fmt, "%s", showPartial(x))]
let parsePartial = version => {
  let version = version.[0] == 'v' ? sliceToEnd(version, 1) : version;
  let parts = String.split_on_char('.', version);
  switch parts {
  | ["*" | "x" | "X", ...rest] => `AllStar
  | [major, "*" | "x" | "X", ...rest] when isint(major) => `MajorStar(int_of_string(major))
  | [major, minor, "*" | "x" | "X", ...rest] when isint(major) && isint(minor) => `MinorStar(int_of_string(major), int_of_string(minor))
  | _ => {
    let rx = Str.regexp({|^\([0-9]+\)\(\.\([0-9]+\)\(\.\([0-9]+\)\)?\)?\(\([-+~][a-z0-9\.]+\)\)?|});
    switch (Str.search_forward(rx, version, 0)) {
      | exception Not_found => `Raw(version)
      | _ => {
        let major = int_of_string(Str.matched_group(1, version));
        let qual = switch (Str.matched_group(7, version)) {
        | exception Not_found => {
          let last = Str.match_end();
          if (last < String.length(version)) {
            Some(sliceToEnd(version, last))
          } else {
            None
          }
        }
        | text => Some(text)
        };
        switch (Str.matched_group(3, version)) {
        | exception Not_found => `Major(major, qual)
        | minor => {
            let minor = int_of_string(minor);
            switch (Str.matched_group(5, version)) {
            | exception Not_found => `Minor(major, minor, qual)
            | patch => `Patch(major, minor, int_of_string(patch), qual)
            }
          }
        }
      }
    }
  }
  }
};
open Shared.GenericVersion;

[@test [
  (">=2.3.1", AtLeast((2,3,1,None))),
  ("<2.4", LessThan((2,4,0,None))),
]]
let parsePrimitive = item => switch (item.[0]) {
| '=' => Exactly(parsePartial(sliceToEnd(item, 1)) |> exactPartial)
| '>' => switch (item.[1]) {
  | '=' => AtLeast(parsePartial(sliceToEnd(item, 2)) |> exactPartial)
  | _ => GreaterThan(parsePartial(sliceToEnd(item, 1)) |> exactPartial)
  }
| '<' => switch (item.[1]) {
  | '=' => AtMost(parsePartial(sliceToEnd(item, 2)) |> exactPartial)
  | _ => LessThan(parsePartial(sliceToEnd(item, 1)) |> exactPartial)
  }
| _ => failwith("Bad primitive")
};

let parseSimple = item => {
  switch (item.[0]) {
  | '~' => switch (parsePartial(sliceToEnd(item, 1))) {
    | `Major(num, q) => And(AtLeast((num, 0, 0, q)), LessThan((num + 1, 0, 0, None)))
    | `Minor(m, i, q) => And(AtLeast((m, i, 0, q)), LessThan((m, i + 1, 0, None)))
    | `Patch(m, i, p, q) => And(AtLeast((m, i, p, q)), LessThan((m, i + 1, 0, None)))
    | `AllStar => failwith("* cannot be tilded")
    | `MajorStar(num) => And(AtLeast((num, 0, 0, None)), LessThan((num + 1, 0, 0, None)))
    | `MinorStar(m, i) => And(AtLeast((m, i, 0, None)), LessThan((m, i + 1, 0, None)))
    | `Raw(_) => failwith("Bad tilde")
    }
  | '^' => switch (parsePartial(sliceToEnd(item, 1))) {
    | `Major(num, q) => And(AtLeast((num, 0, 0, q)), LessThan((num + 1, 0, 0, None)))
    | `Minor(0, i, q) => And(AtLeast((0, i, 0, q)), LessThan((0, i + 1, 0, None)))
    | `Minor(m, i, q) => And(AtLeast((m, i, 0, q)), LessThan((m + 1, 0, 0, None)))
    | `Patch(0, 0, p, q) => And(AtLeast((0, 0, p, q)), LessThan((0, 0, p + 1, None)))
    | `Patch(0, i, p, q) => And(AtLeast((0, i, p, q)), LessThan((0, i + 1, 0, None)))
    | `Patch(m, i, p, q) => And(AtLeast((m, i, p, q)), LessThan((m + 1, 0, 0, None)))
    | `AllStar => failwith("* cannot be careted")
    | `MajorStar(num) => And(AtLeast((num, 0, 0, None)), LessThan((num + 1, 0, 0, None)))
    | `MinorStar(m, i) => And(AtLeast((m, i, 0, None)), LessThan((m + 1, i, 0, None)))
    | `Raw(_) => failwith("Bad tilde")
    }
  | '>' | '<' | '=' => parsePrimitive(item)
  | _ => switch(parsePartial(item)) {
    | `AllStar => Any
    /* TODO maybe handle the qualifier */
    | `Major(m, Some(x)) => Exactly((m, 0, 0, Some(x)))
    | `Major(m, None)
    | `MajorStar(m) => And(AtLeast((m, 0, 0, None)), LessThan((m + 1, 0, 0, None)))
    | `Minor(m, i, Some(x)) => Exactly((m, i, 0, Some(x)))
    | `Minor(m, i, None)
    | `MinorStar(m, i) => And(AtLeast((m, i, 0, None)), LessThan((m, i + 1, 0, None)))
    | `Patch(m, i, p, q) => Exactly((m, i, p, q))
    | `Raw(text) => Exactly((0, 0, 0, Some(text)))
  }
  }
};

let parseSimples = (item, parseSimple) => {
  let item = item
  |> Str.global_replace(Str.regexp(">= +"), ">=")
  |> Str.global_replace(Str.regexp("<= +"), "<=")
  |> Str.global_replace(Str.regexp("> +"), ">")
  |> Str.global_replace(Str.regexp("< +"), "<")
  ;
  let items = String.split_on_char(' ', item);
  let rec loop = items => switch items {
  | [item] => parseSimple(item)
  | [item, ...items] => And(parseSimple(item), loop(items))
  | [] => assert(false)
  };
  loop(items)
};

[@test Shared.GenericVersion.([
  ("1.2.3", Exactly((1,2,3,None))),
  ("1.2.3-alpha2", Exactly((1,2,3,Some("-alpha2")))),
  ("1.2.3 - 2.3.4", And(AtLeast((1,2,3,None)), AtMost((2,3,4,None)))),
  ("1.2.3 - 2.3", And(AtLeast((1,2,3,None)), LessThan((2,4,0,None)))),
])]
[@test.print (fmt, v) => Format.fprintf(fmt, "%s", viewRange(v))]
let parseNpmRange = (simple) => {
  let items = Str.split(Str.regexp(" +- +"), simple);
  switch items {
  | [item] => parseSimples(item, parseSimple)
  | [left, right] => {
    let left = AtLeast(parsePartial(left) |> exactPartial);
    let right = switch (parsePartial(right)) {
      | `AllStar => Any
      /* TODO maybe handle the qualifier */
      | `Major(m, _)
      | `MajorStar(m) => LessThan((m + 1, 0, 0, None))
      | `Minor(m, i, _)
      | `MinorStar(m, i) => LessThan((m, i + 1, 0, None))
      | `Patch(m, i, p, q) => AtMost((m, i, p, q))
      | `Raw(text) => LessThan((0, 0, 0, Some(text)))
    };
    And(left, right)
  }
  | _ => failwith("Invalid range")
  }
};

[@test Shared.GenericVersion.([
  ("1.2.3", Exactly((1,2,3,None))),
  ("1.2.3-alpha2", Exactly((1,2,3,Some("-alpha2")))),
  ("1.2.3 - 2.3.4", And(AtLeast((1,2,3,None)), AtMost((2,3,4,None)))),
  ("1.2.3 - 2.3 || 5.x", Or(And(AtLeast((1,2,3,None)), LessThan((2,4,0,None))), And(AtLeast((5, 0, 0, None)), LessThan((6, 0, 0, None))))),
])]
[@test.call parseOrs(parseNpmRange)]
[@test.print (fmt, v) => Format.fprintf(fmt, "%s", viewRange(v))]
let parseOrs = (parseRange, version) => {
  if (version == "") {
    Shared.GenericVersion.Any
  } else {
    let items = Str.split(Str.regexp(" +|| +"), version);
    let rec loop = items => switch items {
    | [] => failwith("WAAAT " ++ version)
    | [item] => parseRange(item)
    | [item, ...items] => Or(parseRange(item), loop(items))
    };
    loop(items)
  }
};

let parse = parseOrs(parseNpmRange);
