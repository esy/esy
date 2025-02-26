/**
 * Represents a project solution (ie. transitive closure of
 * dependencies needed by a project)
 */

open DepSpec;
open EsyPackageConfig;
open EsyPrimitives;

type id = PackageId.t;
type pkg = Package.t;
type traverse = pkg => list(id);
type t;

let empty: id => t;
let add: (t, pkg) => t;
let nodes: t => list(pkg);

let root: t => pkg;
let isRoot: (t, pkg) => bool;

let dependenciesBySpec: (t, FetchDepsSubset.t, pkg) => list(pkg);
let dependenciesByDepSpec: (t, FetchDepSpec.t, pkg) => list(pkg);

let mem: (t, id) => bool;
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

/**

   Returns the children of a node as a list

 */
let traverse: pkg => list(id);

/**
 * [eval solution self depspec] evals [depspec] given the [solution] and the
 * current package id [self].
 */

let eval: (t, FetchDepSpec.t, PackageId.t) => PackageId.Set.t;

/**
 * [collect solution depspec id] collects all package ids found in the
 * [solution] starting with [id] using [depspec] expression for traverse.
 */

let collect: (t, FetchDepSpec.t, PackageId.t) => PackageId.Set.t;

/**
   Returns a list of dependencies that don't,ca build on other platforms. The default list of platforms
   (os, arch) tuples are list in [DefaultPlatforms]
*/
let unPortableDependencies:
  (~expected: EsyOpamLibs.AvailablePlatforms.t, t) =>
  RunAsync.t(list((pkg, EsyOpamLibs.AvailablePlatforms.t)));
