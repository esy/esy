
/*
 * High level handling of npm versions
 */

let viewConcrete = ((m, i, p, r)) => {
  ([m, i, p] |> List.map(string_of_int) |> String.concat("."))
  ++
  switch r { | None => "" | Some(a) => a}
};
let viewRange = Shared.GenericVersion.view(viewConcrete);

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

[@test Shared.GenericVersion.([
  ("~1.2.3", parseRange(">=1.2.3 <1.3.0")),
  ("~1.2", parseRange(">=1.2.0 <1.3.0")),
  ("~1.2", parseRange("1.2.x")),
  ("~1", parseRange(">=1.0.0 <2.0.0")),
  ("~1", parseRange("1.x")),
  ("~0.2.3", parseRange(">=0.2.3 <0.3.0")),
  ("~0", parseRange("0.x")),

  ("1.2.3", Exactly((1,2,3,None))),
  ("1.2.3-alpha2", Exactly((1,2,3,Some("-alpha2")))),
  ("1.2.3 - 2.3.4", And(AtLeast((1,2,3,None)), AtMost((2,3,4,None)))),
])]
[@test.print (fmt, v) => Format.fprintf(fmt, "%s", viewRange(v))]
let parseRange = version => {
  try (ParseNpm.parse(version)) {
  | Failure(message) => {
    print_endline("Failed with message: " ++ message ++ " : " ++ version);
    Any
  }
  | e => {
    print_endline("Invalid version! pretending its any: " ++ version ++ " " ++ Printexc.to_string(e));
    Any
  }
  }
};

let isint = v => try ({ignore(int_of_string(v)); true}) { | _ => false };

let getRest = parts => parts == [] ? None : Some(String.concat(".", parts));

let parseConcrete = version => {
  let parts = String.split_on_char('.', version);
  switch parts {
  | [major, minor, patch, ...rest] when isint(major) && isint(minor) && isint(patch) =>
    (int_of_string(major), int_of_string(minor), int_of_string(patch), getRest(rest))
  | [major, minor, ...rest] when isint(major) && isint(minor) =>
    (int_of_string(major), int_of_string(minor), 0, getRest(rest))
  | [major, ...rest] when isint(major) =>
    (int_of_string(major), 0, 0, getRest(rest))
  | rest =>
    (0, 0, 0, getRest(rest))
  }
};

let after = (a, prefix) => {
  let al = String.length(a);
  let pl = String.length(prefix);
  if (al > pl && String.sub(a, 0, pl) == prefix) {
    Some(String.sub(a, pl, al - pl))
  } else {
    None
  }
};

let compareExtra = (a, b) => {
  switch (a, b) {
  | (Some(a), Some(b)) => {
    switch (after(a, "-beta"), after(b, "-beta")) {
    | (Some(a), Some(b)) => try(int_of_string(a) - int_of_string(b)) { | _ => compare(a, b) }
    | _ => switch (after(a, "-alpha"), after(b, "-alpha")) {
      | (Some(a), Some(b)) => try(int_of_string(a) - int_of_string(b)) { | _ => compare(a, b) }
      | _ => try(int_of_string(a) - int_of_string(b)) { | _ => compare(a, b) }
      }
    }
  }
  | _ => compare(a, b)
  }
};

let compare = ((ma, ia, pa, ra), (mb, ib, pb, rb)) => {
  ma != mb
  ? (ma - mb)
  : (
    ia != ib
    ? (ia - ib)
    : (
      pa != pb
      ? (pa - pb)
      : compareExtra(ra, rb)
    )
  )
};

let matches = Shared.GenericVersion.matches(compare);
