/** Dependency specification language */;

module type DEPSPEC = {
  type id;

  type t =
    pri
      | Package(id) | Dependencies(id) | DevDependencies(id) | Union(t, t);
  /* term */

  let package: id => t;
  /* refer to a package defined by source */

  let dependencies: id => t;
  /* refer to dependencies defined by source */

  let devDependencies: id => t;
  /* refer to devDependencies defined by source */

  /** [union a b] produces a new term with all packages defined by [a] and * [b] */

  let union: (t, t) => t;

  /** [a + b] is the same as [union a b] */

  let (+): (t, t) => t;

  let compare: (t, t) => int;
  let pp: (Format.formatter, t) => unit;
};

module type ID = {
  type t;

  let compare: (t, t) => int;
  let pp: (Format.formatter, t) => unit;
};

module Make: (Id: ID) => DEPSPEC with type id = Id.t;
