
[@deriving yojson]
type range('inner) =
  | Or(range('inner), range('inner))
  | And(range('inner), range('inner))
  | Exactly('inner)
  | GreaterThan('inner)
  | AtLeast('inner)
  | LessThan('inner)
  | AtMost('inner)
  | Nothing
  | Any;
  /* | UntilNextMajor('concrete) | UntilNextMinor('concrete); */

/** TODO want a way to exclude npm -alpha items when they don't apply */

let rec matches = (compareInner, range, concrete) => {
  switch range {
  | Exactly(a) => compareInner(a, concrete) == 0
  | Any => true
  | Nothing => false
  | GreaterThan(a) => compareInner(a, concrete) < 0
  | AtLeast(a) => compareInner(a, concrete) <= 0
  | LessThan(a) => compareInner(a, concrete) > 0
  | AtMost(a) => compareInner(a, concrete) >= 0
  | And(a, b) => matches(compareInner, a, concrete) && matches(compareInner, b, concrete)
  | Or(a, b) => matches(compareInner, a, concrete) || matches(compareInner, b, concrete)
  }
};

let rec isTooLarge = (compareInner, range, concrete) => {
  switch range {
  | Exactly(a) => compareInner(a, concrete) < 0
  | Any => false
  | Nothing => false
  | GreaterThan(a) => false
  | AtLeast(a) => false
  | LessThan(a) => compareInner(a, concrete) <= 0
  | AtMost(a) => compareInner(a, concrete) < 0
  | And(a, b) => isTooLarge(compareInner, a, concrete) || isTooLarge(compareInner, b, concrete)
  | Or(a, b) => isTooLarge(compareInner, a, concrete) && isTooLarge(compareInner, b, concrete)
  }
};

let rec view = (viewInner, range) => {
  switch range {
  | Exactly(a) => viewInner(a)
  | Any => "*"
  | Nothing => "none"
  | GreaterThan(a) => "> " ++ viewInner(a)
  | AtLeast(a) => ">= " ++ viewInner(a)
  | LessThan(a) => "< " ++ viewInner(a)
  | AtMost(a) => "<= " ++ viewInner(a)
  | And(a, b) => view(viewInner, a) ++ " && " ++ view(viewInner, b)
  | Or(a, b) => view(viewInner, a) ++ " || " ++ view(viewInner, b)
  }
};

let rec map = (transform, range) => {
  switch range {
  | Exactly(a) => Exactly(transform(a))
  | Any => Any
  | Nothing => Nothing
  | GreaterThan(a) => GreaterThan(transform(a))
  | AtLeast(a) => AtLeast(transform(a))
  | LessThan(a) => LessThan(transform(a))
  | AtMost(a) => AtMost(transform(a))
  | And(a, b) => And(map(transform, a), map(transform, b))
  | Or(a, b) => Or(map(transform, a), map(transform, b))
  }
};