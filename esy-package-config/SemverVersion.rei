module Version: {
  include (module type of Semver.Version);

  include S.COMMON with type t := t;
  include S.SEXPABLE with type t := t;

  let parser: Parse.t(t);
};

module Formula: {
  include (module type of Semver.Formula.DNF);

  let any: t;

  let parserDnf: Parse.t(t);

  let parse: string => result(t, string);
  let parseExn: string => t;
};

let caretRangeOfVersion: Version.t => Formula.t;
