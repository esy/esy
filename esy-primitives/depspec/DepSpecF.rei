module type T = {
  /** Package id. */
  type id;

  type t =
    pri
      | Package(id) | Dependencies(id) | DevDependencies(id) | Union(t, t);
  /* terms of depspec expression */

  let package: id => t;
  /** [package(id)] refers to a package by its [id] defined by source. */

  let dependencies: id => t;
  /** [dependencies(id)] refers all dependencies of the package with [id] defined by source. */

  let devDependencies: id => t;
  /** [dependencies(id)] refers all devDependencies of the package with [id] defined by source. */

  /** [union a b] produces a new term with all packages defined by [a] and * [b] */

  let union: (t, t) => t;

  /** [a + b] is the same as [union a b] - ie all packages in [a] and in [b] */

  let (+): (t, t) => t;

  let compare: (t, t) => int;
  let pp: (Format.formatter, t) => unit;
};

module type ID = {
  type t;

  let compare: (t, t) => int;
  let pp: (Format.formatter, t) => unit;
};

module Make: (Id: ID) => T with type id = Id.t;
