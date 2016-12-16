/**
 * @flow
 */

const resolve = require('resolve');
const path = require('path');
const fs = require('fs');

/**
 * Package database is an information about packages currently installed in a
 * sandbox and dependencies between them.
 */

export type PackageDb = {

  /**
   * Absolute path to the root of the sandbox.
   */
  path: string;

  /**
   * Name of the package at the root of the sandbox.
   *
   * This package is a "main" package in the sandbox. All standard esy commands
   * like `build`/`shell`/... operate on this package by default.
   */
  rootPackageName: string;

  packagesByName: {
    [name: string]: PackageInfo;
  };
};

export type PackageInfo = {
  /**
   * Normalized name of the package which is safe to use in shell environment
   * variables.
   */
  normalizedName: string;

  /**
   * Absolute path to the package's package.json.
   *
   * Make sure you don't use it in the ejected build code.
   */
  packageJsonFilePath: string;

  packageJson: PackageJson;
};

export type PackageJson = {
  name: string;
  version?: string;
  dependencies?: PackageJsonVersionSpec;
  peerDependencies?: PackageJsonVersionSpec;
  devDependencies?: PackageJsonVersionSpec;
  optionalDependencies?: PackageJsonVersionSpec;

  pjc?: {
    build?: string;
  };

  exportedEnvVars?: {
    [name: string]: EnvironmentVarExport;
  }
};

export type EnvironmentVarExport = {
  val: string;
  scope?: string;
  exclusive?: boolean;
  __BUILT_IN_DO_NOT_USE_OR_YOU_WILL_BE_PIPd?: boolean;
};

export type PackageJsonVersionSpec = {
  [name: string]: string;
};

const KEYS = [
  'dependencies',
  'peerDependencies',
];

/**
 * Create a package database from a given directory.
 */
function fromDirectory(dir: string): PackageDb {

  const packageJsonFilePath = path.join(dir, 'package.json');

  if (!fs.existsSync(packageJsonFilePath)) {
    throw new Error(
      `Invalid sandbox: no ${path.relative(process.cwd(), packageJsonFilePath)} ` +
      `found. Every valid sandbox must have one.`
    )
  }

  const packagesByName = {};
  let rootPackageName = null;

  traversePackageTreeOnFileSystemSync(
    path.join(dir, 'package.json'),
    (packageJsonFilePath, packageJson) => {
      rootPackageName = packageJson.name;
      packagesByName[packageJson.name] = {
        normalizedName: normalizeName(packageJson.name),
        packageJsonFilePath,
        packageJson,
      };
    });

  if (rootPackageName == null) {
    throw new Error('empty package db');
  }

  return {
    path: dir,
    rootPackageName,
    packagesByName,
  };
}

function collectDependencies(
  packageDb: PackageDb,
  packageName: string
): Array<string> {
  let packageInfo = packageDb.packagesByName[packageName];
  if (packageInfo == null) {
    throw new Error(`Unknown package: ${packageName}`);
  }
  let {packageJson} = packageInfo
  let dependencies = [];
  if (packageJson.dependencies != null) {
    dependencies = dependencies.concat(Object.keys(packageJson.dependencies));
  }
  if (packageJson.peerDependencies != null) {
    dependencies = dependencies.concat(Object.keys(packageJson.peerDependencies));
  }
  return dependencies;
}

function collectTransitiveDependencies(
  packageDb: PackageDb,
  packageName: string
): Array<string> {
  let packageInfo = packageDb.packagesByName[packageName];
  if (packageInfo == null) {
    throw new Error(`Unknown package: ${packageName}`);
  }
  let packageJson = packageInfo.packageJson;
  let dependencies = collectDependencies(packageDb, packageName);
  let set = new Set(dependencies);
  for (let dep of dependencies) {
    for (let subdep of collectTransitiveDependencies(packageDb, dep)) {
      set.add(subdep);
    }
  }
  return Array.from(set);
}

function traversePackageDb(
  packageDb: PackageDb,
  handler: (packageInfo: PackageInfo) => *,
  packageName?: string = packageDb.rootPackageName
) {
  let packageInfo = packageDb.packagesByName[packageName];
  let seen = new Set();
  traversePackageDbImpl(
    packageInfo,
    seen,
    packageDb,
    handler
  );
}

function traversePackageDbImpl(
  packageInfo,
  seen,
  packageDb,
  handler
) {
  let {packageJson, packageJsonFilePath} = packageInfo;
  let dependencies = collectDependencies(packageDb, packageJson.name);
  for (let depName of dependencies) {
    if (seen.has(depName)) {
      continue;
    }
    seen.add(depName);
    let depPackageInfo = packageDb.packagesByName[depName];
    traversePackageDbImpl(
      depPackageInfo,
      seen,
      packageDb,
      handler
    );
  }
  handler(packageInfo)
}

function traversePackageTreeOnFileSystemSync(
  packageJsonPathOnEjectingHost,
  handler,
  visitedRealPaths = {}
) {
  const packageJsonPathOnEjectingHostRealPath = fs.realpathSync(packageJsonPathOnEjectingHost);
  const pkg = JSON.parse(fs.readFileSync(packageJsonPathOnEjectingHost, 'utf8'));
  if (!pkg.name) {
    throw ("no package name for package:" + packageJsonPathOnEjectingHost);
  }
  visitedRealPaths[pkg.name] = packageJsonPathOnEjectingHostRealPath;
  /**
   * How about the convention that `buildTimeOnlyDependencies` won't be
   * traversed transitively to compute environments. The primary use case is
   * that we generally only need a binary produced - or a dll.
   */
  KEYS.forEach((key) => {
    Object.keys(pkg[key] || {}).forEach((dependencyName) => {
      try {
        const resolved = resolve.sync(
          path.join(dependencyName, 'package.json'),
          {basedir: path.dirname(packageJsonPathOnEjectingHost)}
        );
        if (!visitedRealPaths[dependencyName]) {
          traversePackageTreeOnFileSystemSync(resolved, handler);
        } else {
          if (visitedRealPaths[dependencyName] !== fs.realpathSync(resolved)) {
            // Find a way to aggregate warnings.
            // console.warn(
            //   "While computing environment for " + pkg.name + ", found that there are two separate packages named " +
            //     dependencyName + " at two different real paths on disk. One is at " +
            //     visitedRealPaths[dependencyName] + " and the other at " + fs.realpathSync(resolved)
            // );
          }
        }
      } catch (err) {
        // We are forgiving on optional dependencies -- if we can't find them,
        // just skip them
        if (pkg["optionalDependencies"] && pkg["optionalDependencies"][dependencyName]) {
          return;
        }
        throw err;
      }
    })
  });
  handler(packageJsonPathOnEjectingHost, pkg);
}

function normalizeName(name) {
  return name
    .toLowerCase()
    .replace(/@/g, '')
    .replace(/\//g, '_')
    .replace(/\-/g, '_');
}

module.exports = {
  fromDirectory,
  traversePackageDb,
  collectTransitiveDependencies,
  collectDependencies,
};
