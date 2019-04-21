/**
 * This module defines utilities for working with versions.
 */;

/**
 * Type for versions.
 *
 * opam's versions and npm's semver versions implement this.
 */

module type VERSION = {
  type t;

  include S.COMMON with type t := t;

  let parser: Parse.t(t);
  let parse: string => result(t, string);
  let parseExn: string => t;

  let majorMinorPatch: t => option((int, int, int));
  let prerelease: t => bool;
  let stripPrerelease: t => t;
};

/**
 * Constraints over versions.
 */

module type CONSTRAINT = {
  type version;
  type t =
    | EQ(version)
    | NEQ(version)
    | GT(version)
    | GTE(version)
    | LT(version)
    | LTE(version)
    | ANY;

  include S.COMMON with type t := t;

  module VersionSet: Set.S with type elt = version;

  let matchesSimple: (~version: version, t) => bool;

  let matches:
    (~matchPrerelease: VersionSet.t=?, ~version: version, t) => bool;

  let map: (~f: version => version, t) => t;
};

/**
 * Formulas over constraints.
 */

module type FORMULA = {
  type version;
  type constr;

  type conj('f) = list('f);
  type disj('f) = list('f);

  /**
   * Disjnuction normal form.
   */

  module DNF: {
    type t = disj(conj(constr));

    include S.COMMON with type t := t;

    let unit: constr => t;
    let matches: (~version: version, t) => bool;
    let map: (~f: version => version, t) => t;

    let conj: (t, t) => t;
    let disj: (disj(constr), disj(constr)) => disj(constr);
  };

  /**
   * Conjunction normal form.
   */

  module CNF: {
    type t = conj(disj(constr));

    include S.COMMON with type t := t;

    let matches: (~version: version, disj(disj(constr))) => bool;
  };

  /**
   * Convert from DNF to CNF.
   */

  let ofDnfToCnf: DNF.t => CNF.t;

  module ParseUtils: {
    let conjunction: (~parse: string => 'a, string) => disj('a);
    let disjunction:
      (~parse: string => disj(constr), string) => disj(disj(constr));
  };
};

module Constraint: {
  module Make: (Version: VERSION) => CONSTRAINT with type version = Version.t;
};

module Formula: {
  module Make:
    (
      Version: VERSION,
      Constraint: CONSTRAINT with type version = Version.t,
    ) =>
     FORMULA with type version = Version.t and type constr = Constraint.t;
};
