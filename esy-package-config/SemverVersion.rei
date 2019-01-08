module Version: {
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

  include VersionBase.VERSION with type t := t;

  let parse: string => result(t, string);
  let sexp_of_t: t => Sexplib0.Sexp.t;
};

module Constraint: VersionBase.CONSTRAINT with type version = Version.t;

module Formula: {
  include
    VersionBase.FORMULA with
      type version = Version.t and type constr = Constraint.t;

  let any: DNF.t;

  let parserDnf: Parse.t(DNF.t);

  let parse: string => result(DNF.t, string);
  let parseExn: string => DNF.t;
};

let caretRangeOfVersion: Version.t => Formula.DNF.t;
