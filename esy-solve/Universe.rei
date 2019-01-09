open EsyPackageConfig;

/**
 * Package universe holds information about available packages.
 */;

/** Package universe. */

type t;
type univ = t;

/** Empty package universe. */

let empty: Resolver.t => t;

/** Add package to the package universe. */

let add: (~pkg: InstallManifest.t, t) => t;

/** Check if the package is a member of the package universe. */

let mem: (~pkg: InstallManifest.t, t) => bool;

/** Find all versions of a package specified by name. */

let findVersions: (~name: string, t) => list(InstallManifest.t);

/** Find a specific version of a package. */

let findVersion:
  (~name: string, ~version: Version.t, t) => option(InstallManifest.t);
let findVersionExn:
  (~name: string, ~version: Version.t, t) => InstallManifest.t;

module CudfName: {
  type t;
  let show: t => string;
  let make: string => t;
};

/**
 * Mapping from universe to CUDF.
 */

module CudfMapping: {
  type t;

  let encodePkgName: string => CudfName.t;
  let decodePkgName: CudfName.t => string;

  let encodePkg: (InstallManifest.t, t) => option(Cudf.package);
  let encodePkgExn: (InstallManifest.t, t) => Cudf.package;

  let decodePkg: (Cudf.package, t) => option(InstallManifest.t);
  let decodePkgExn: (Cudf.package, t) => InstallManifest.t;

  let univ: t => univ;
  let cudfUniv: t => Cudf.universe;
};

/**
 * Encode universe as CUDF>
 */

let toCudf:
  (~installed: InstallManifest.Set.t=?, SolveSpec.t, t) =>
  (Cudf.universe, CudfMapping.t);
