open Shared.Types;
open Shared;

/**
 * This file is about parsing opam versions from `package.json` specifications.
 * So the concrete versions are opam (following the "interspersed alpha and numeric"
 * pattern), but the range syntax is what you get in npm.
 * So ^1.0+beta5 becomes >= 1.0-beta5 && < 2
 */

let triple = (major, minor, patch) => {
  Shared.Types.opamFromNpmConcrete((major, minor, patch, None))
};

[@test [
  (("123abc", 0), 3),
  (("a123abc", 1), 4),
  (("abc", 1), 1),
  (("abc", 3), 3),
]]
let rec getNums = (text, pos) => {
  if (pos < String.length(text)) {
    switch (text.[pos]) {
    | '0'..'9' => getNums(text, pos + 1)
    | _ => pos
    }
  } else {
    pos
  }
};

let rec getNonNums = (text, pos) => {
  if (pos < String.length(text)) {
    switch (text.[pos]) {
    | '0'..'9' => pos
    | _ => getNonNums(text, pos + 1)
    }
  } else {
    pos
  }
};

[@test [
  ("1.2.3", triple(1,2,3)),
  ("1.2.3~alpha", Shared.Types.opamFromNpmConcrete((1,2,3, Some("~alpha")))),
]]
let parseConcrete = text => {
  let len = String.length(text);
  let rec getNum = (pos) => {
    if (pos >= len) {
      None
    } else {
      let tpos = getNums(text, pos);
      let num = String.sub(text, pos, tpos - pos);
      Some(Num(int_of_string(num), getString(tpos)))
    }
  } and getString = pos => {
    if (pos >= len) {
      None
    } else switch (text.[pos]) {
    | '0'..'9' => Some(Alpha("", getNum(pos)))
    | _ => {
      let tpos = getNonNums(text, pos);
      let t = String.sub(text, pos, tpos - pos);
      Some(Alpha(t, getNum(tpos)))
    }
    }
  };
  switch (getString(0)) {
  | None => Alpha("", None)
  | Some(a) => a
  }
};

let rec findNextForTilde = (Alpha(t, n)) => {
  if (t == "." || t == "") {
    switch n {
    | None => `End
    | Some(Num(n, rest)) => {
      switch rest {
      | None => `LastNum(Alpha(t, Some(Num(n + 1, None))))
      | Some(rest) => switch (findNextForTilde(rest)) {
        | `End => `LastNum(Alpha(t, Some(Num(n + 1, None))))
        | `LastNum(_) => `Done(Alpha(t, Some(Num(n + 1, None))))
        | `Done(rest) => `Done(Alpha(t, Some(Num(n, Some(rest)))))
        }
      }
    }
    }
  } else {
    `End
  }
};

[@test [
  (parseConcrete("1.2.3"), parseConcrete("1.3")),
  (parseConcrete("1.5.4-alpha6"), parseConcrete("1.6")),
  (parseConcrete("1.2"), parseConcrete("2")),
]]
[@test.print (fmt, t) => Format.fprintf(fmt, "%s", Types.viewOpamConcrete(t))]
let findNextForTilde = (version) => switch (findNextForTilde(version)) {
| `End => failwith("Cannot tilde a version with no numbers")
| `LastNum(version) => version
| `Done(version) => version
};

[@test [
  (parseConcrete("1.2.3"), parseConcrete("2")),
  (parseConcrete("0.2.3"), parseConcrete("0.3")),
]]
[@test.print (fmt, t) => Format.fprintf(fmt, "%s", Types.viewOpamConcrete(t))]
let rec findNextForCaret = (Alpha(t, n)) => {
  if (t == "." || t == "") {
    switch n {
    | None => failwith("No nonzero numbers")
    | Some(Num(0, rest)) => {
      switch rest {
      | None => failwith("No nonzero numbers")
      | Some(rest) => Alpha(t, Some(Num(0, Some(findNextForTilde(rest)))))
      }
    }
    | Some(Num(n, rest)) => {
      Alpha(t, Some(Num(n + 1, None)))
    }
    }
  } else {
    failwith("No nonzero numbers")
  }
};

let parseOpamSimple = text => {
  if (text == "*") {
    GenericVersion.Any
  } else if (text == "") {
    GenericVersion.Any
  } else if (text.[0] == '^') {
    let version = parseConcrete(ParseNpm.sliceToEnd(text, 1));
    let next = findNextForCaret(version);
    GenericVersion.(
      And(AtLeast(version), LessThan(next))
    )
  } else if (text.[0] == '~') {
    let version = parseConcrete(ParseNpm.sliceToEnd(text, 1));
    let next = findNextForTilde(version);
    GenericVersion.(
      And(AtLeast(version), LessThan(next))
    )
  } else if (text.[0] == '=') {
    GenericVersion.Exactly(parseConcrete(ParseNpm.sliceToEnd(text, 1)))
  } else if (text.[0] == '<' && text.[1] == '=') {
    GenericVersion.AtMost(parseConcrete(ParseNpm.sliceToEnd(text, 2)))
  } else if (text.[0] == '<') {
    GenericVersion.LessThan(parseConcrete(ParseNpm.sliceToEnd(text, 1)))
  } else if (text.[0] == '>' && text.[1] == '=') {
    GenericVersion.AtLeast(parseConcrete(ParseNpm.sliceToEnd(text, 2)))
  } else if (text.[0] == '>') {
    GenericVersion.GreaterThan(parseConcrete(ParseNpm.sliceToEnd(text, 1)))
  } else {
    GenericVersion.Exactly(parseConcrete(text))
  }
};

let parseNpmRange = ParseNpm.parseOrs(text => ParseNpm.parseSimples(text, parseOpamSimple));