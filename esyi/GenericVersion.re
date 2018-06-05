[@deriving yojson]
type range('inner) =
  | OR(range('inner), range('inner))
  | AND(range('inner), range('inner))
  | EQ('inner)
  | GT('inner)
  | GTE('inner)
  | LT('inner)
  | LTE('inner)
  | NONE
  | ANY;

/* | UntilNextMajor('concrete) | UntilNextMinor('concrete); */
/** TODO want a way to exclude npm -alpha items when they don't apply */
let rec matches = (compareInner, range, concrete) =>
  switch (range) {
  | EQ(a) => compareInner(a, concrete) == 0
  | ANY => true
  | NONE => false
  | GT(a) => compareInner(a, concrete) < 0
  | GTE(a) => compareInner(a, concrete) <= 0
  | LT(a) => compareInner(a, concrete) > 0
  | LTE(a) => compareInner(a, concrete) >= 0
  | AND(a, b) =>
    matches(compareInner, a, concrete) && matches(compareInner, b, concrete)
  | OR(a, b) =>
    matches(compareInner, a, concrete) || matches(compareInner, b, concrete)
  };

let rec isTooLarge = (compareInner, range, concrete) =>
  switch (range) {
  | EQ(a) => compareInner(a, concrete) < 0
  | ANY => false
  | NONE => false
  | GT(_a) => false
  | GTE(_a) => false
  | LT(a) => compareInner(a, concrete) <= 0
  | LTE(a) => compareInner(a, concrete) < 0
  | AND(a, b) =>
    isTooLarge(compareInner, a, concrete)
    || isTooLarge(compareInner, b, concrete)
  | OR(a, b) =>
    isTooLarge(compareInner, a, concrete)
    && isTooLarge(compareInner, b, concrete)
  };

let rec view = (viewInner, range) =>
  switch (range) {
  | EQ(a) => viewInner(a)
  | ANY => "*"
  | NONE => "none"
  | GT(a) => "> " ++ viewInner(a)
  | GTE(a) => ">= " ++ viewInner(a)
  | LT(a) => "< " ++ viewInner(a)
  | LTE(a) => "<= " ++ viewInner(a)
  | AND(a, b) => view(viewInner, a) ++ " && " ++ view(viewInner, b)
  | OR(a, b) => view(viewInner, a) ++ " || " ++ view(viewInner, b)
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
