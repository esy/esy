open EsyPackageConfig;

/**
 * This module represents a solution.
 */;

module DepSpec: {
  /** Package id. */

  type id;

  let root: id;
  let self: id;

  /** Dependency expression, */

  type t;

  /** [package id] refers to a package by its [id]. */

  let package: id => t;

  /** [dependencies id] refers all dependencies of the package with [id]. */

  let dependencies: id => t;

  /** [dependencies id] refers all devDependencies of the package with [id]. */

  let devDependencies: id => t;

  /** [a + b] refers to all packages in [a] and in [b]. */

  let (+): (t, t) => t;

  let compare: (t, t) => int;
  let pp: Fmt.t(t);
};

module Spec: {
  type t = {
    /***
     Define how we traverse packages.
     */
    all: DepSpec.t,
    /***
     Define how we traverse packages "in-dev".
     */
    dev: DepSpec.t,
  };

  let everything: t;
};

type id = PackageId.t;
type pkg = Package.t;
type traverse = pkg => list(id);
type t;

let empty: id => t;
let add: (t, pkg) => t;
let nodes: t => list(pkg);

let root: t => pkg;
let isRoot: (t, pkg) => bool;

let dependenciesBySpec: (t, Spec.t, pkg) => list(pkg);
let dependenciesByDepSpec: (t, DepSpec.t, pkg) => list(pkg);

let get: (t, id) => option(pkg);
let getExn: (t, id) => pkg;
let findBy: (t, (id, pkg) => bool) => option((id, pkg));
let allDependenciesBFS:
  (~traverse: traverse=?, ~dependencies: list(id)=?, t, id) =>
  list((bool, pkg));
let fold: (~f: (pkg, list(pkg), 'v) => 'v, ~init: 'v, t) => 'v;

let findByPath: (DistPath.t, t) => option(pkg);
let findByName: (string, t) => option(pkg);
let findByNameVersion: (string, Version.t, t) => option(pkg);

let traverse: pkg => list(id);

/**
 * [eval solution self depspec] evals [depspec] given the [solution] and the
 * current package id [self].
 */

let eval: (t, DepSpec.t, PackageId.t) => PackageId.Set.t;

/**
 * [collect solution depspec id] collects all package ids found in the
 * [solution] starting with [id] using [depspec] expression for traverse.
 */

let collect: (t, DepSpec.t, PackageId.t) => PackageId.Set.t;
