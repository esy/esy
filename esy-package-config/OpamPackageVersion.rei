module Version: {
  include VersionBase.VERSION with type t = OpamPackage.Version.t;

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
