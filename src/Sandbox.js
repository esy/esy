/**
 * @flow
 */

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const outdent = require('outdent');
const resolveSync = require('resolve').sync;
const {mapObject} = require('./Utility');

/**
 * Represents sandbox state.
 *
 * Sandbox declaration:
 *
 *    {
 *      env: env,
 *      packageInfo: packageInfo
 *    }
 *
 * Environment override:
 *
 *    {
 *      env: env {
 *        esy__target_architecture: 'arm'
 *      },
 *      packageInfo: packageInfo
 *    }
 *
 */
export type Sandbox = {
  env: Environment;
  packageInfo: PackageInfo;
};

/**
 * Sandbox build environment is a set of k-v pairs.
 */
export type Environment = {[name: string]: string};

export type PackageInfo = {
  source: string;
  sourceType: 'remote' | 'local',
  normalizedName: string;
  rootDirectory: string;
  packageJson: PackageJson;
  dependencyTree: DependencyTree;

  __cachedPackageHash?: string;
};

export type PackageJsonVersionSpec = {
  [name: string]: string;
};

export type EnvironmentVarExport = {
  val: string;
  scope?: string;
  exclusive?: boolean;
  __BUILT_IN_DO_NOT_USE_OR_YOU_WILL_BE_PIPd?: boolean;
};

export type EsyConfig = {
  build: ?string;
  buildsInSource: boolean;
  exportedEnv: {
    [name: string]: EnvironmentVarExport;
  }
};

export type PackageJson = {
  name: string;
  version?: string;
  dependencies?: PackageJsonVersionSpec;
  peerDependencies?: PackageJsonVersionSpec;
  devDependencies?: PackageJsonVersionSpec;
  optionalDependencies?: PackageJsonVersionSpec;

  // This is specific to npm, make sure we get rid of that if we want to port to
  // other package installers.
  //
  // npm puts a resolved name there, for example for packages installed from
  // github — it would be a URL to git repo and a sha1 hash of the tree.
  _resolved?: string;

  esy: EsyConfig;
};

export type DependencyTree = {
  [dependencyName: string]: PackageInfo;
};

function fromDirectory(directory: string): Sandbox {
  const source = path.resolve(directory);
  const env = getEnvironment();
  const packageJson = readPackageJson(path.join(directory, 'package.json'));
  const depSpecList = objectToDependencySpecList(
    packageJson.dependencies,
    packageJson.peerDependencies
  );
  if (depSpecList.length > 0) {
    const dependencyTree = buildDependencyTree(
      source,
      depSpecList,
      {
        packageDependencyTrace: [packageJson.name],
        packageCache: new Map()
      }
    );
    return {
      env,
      packageInfo: {
        source: `local:${fs.realpathSync(source)}`,
        sourceType: 'local',
        normalizedName: normalizeName(packageJson.name),
        rootDirectory: source,
        packageJson,
        dependencyTree,
      }
    };
  } else {
    return {
      env,
      packageInfo: {
        source: `local:${fs.realpathSync(source)}`,
        sourceType: 'local',
        normalizedName: normalizeName(packageJson.name),
        rootDirectory: source,
        packageJson,
        dependencyTree: {}
      }
    };
  }
}

/**
 * Traverse package dependency tree.
 */
function traversePackageDependencyTree(
  packageInfo: PackageInfo,
  handler: (packageInfo: PackageInfo) => *
): void {
  let seen = new Set();
  traversePackageDependencyTreeImpl(
    packageInfo,
    seen,
    handler
  );
}

function traversePackageDependencyTreeImpl(
  packageInfo,
  seen,
  handler
) {
  let {dependencyTree} = packageInfo;
  for (let dependencyName in dependencyTree) {
    if (seen.has(dependencyName)) {
      continue;
    }
    seen.add(dependencyName);
    traversePackageDependencyTreeImpl(
      dependencyTree[dependencyName],
      seen,
      handler
    );
  }
  handler(packageInfo)
}

function collectTransitiveDependencies(
  packageInfo: PackageInfo,
  seen: Set<string> = new Set()
): Array<PackageInfo> {
  let packageJson = packageInfo.packageJson;
  let dependencies = Object.keys(packageInfo.dependencyTree);
  let result = [];
  for (let depName of dependencies) {
    let dep = packageInfo.dependencyTree[depName];
    if (seen.has(depName)) {
      continue;
    }
    seen.add(depName);
    result.push(dep);
    result = result.concat(collectTransitiveDependencies(dep, seen));
  }
  return result;
}

function getEnvironment() {
  let platform = process.env.ESY__TEST ? 'platform' : process.platform;
  let architecture = process.env.ESY__TEST ? 'architecture' : process.arch;
  return {
    'PATH': '/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin',
    'SHELL': 'env -i /bin/bash --norc --noprofile',

    // platform and architecture of the host machine
    'esy__platform': platform,
    'esy__architecture': architecture,

    // platform and architecture of the target machine, so that we can do cross
    // compilation
    'esy__target_platform': platform,
    'esy__target_architecture': architecture,
  };
}

function buildDependencyTree(
  baseDir: string,
  dependencySpecList: Array<string>,
  context: {
    packageDependencyTrace: Array<string>;
    packageCache: Map<string, PackageInfo>;
  }
): DependencyTree {
  let dependencyTree: {[name: string]: PackageInfo} = {};
  for (let dependencySpec of dependencySpecList) {
    const {name} = parseDependencySpec(dependencySpec);
    const dependencyPackageJsonPath  = fs.realpathSync(resolveSync(
      `${name}/package.json`, {basedir: baseDir}));

    let packageInfo = context.packageCache.get(dependencyPackageJsonPath);

    if (packageInfo == null) {
      const dependencyBaseDir = path.dirname(dependencyPackageJsonPath);
      const packageJson = readPackageJson(dependencyPackageJsonPath);
      const depSpecList = objectToDependencySpecList(
        packageJson.dependencies,
        packageJson.peerDependencies
      );

      packageInfo = {
        version: packageJson.version,
        source: packageJson._resolved || `local:${fs.realpathSync(dependencyBaseDir)}`,
        sourceType: packageJson._resolved ? 'remote' : 'local',
        rootDirectory: dependencyBaseDir,
        packageJson,
        normalizedName: normalizeName(packageJson.name),
        dependencyTree: depSpecList.length > 0
          ? buildDependencyTree(
              dependencyBaseDir,
              depSpecList,
              {
                packageCache: context.packageCache,
                packageDependencyTrace: context.packageDependencyTrace.concat(packageJson.name),
              })
          : {}
      };

      context.packageCache.set(dependencyPackageJsonPath, packageInfo);
    };

    dependencyTree[name] = packageInfo;
  }
  return dependencyTree;
}

function readJson(filename) {
  const data = fs.readFileSync(filename, 'utf8');
  return JSON.parse(data);
}

function readPackageJson(filename): PackageJson {
  const packageJson = readJson(filename);
  if (packageJson.esy == null) {
    packageJson.esy = {
      build: null,
      exportedEnv: {},
      buildsInSource: false,
    };
  }
  if (packageJson.esy.build == null) {
    packageJson.esy.build = null;
  }
  if (packageJson.esy.exportedEnv == null) {
    packageJson.esy.exportedEnv = {};
  }
  if (packageJson.esy.buildsInSource == null) {
    packageJson.esy.buildsInSource = false;
  }
  return packageJson;
}

function parseDependencySpec(spec: string): {name: string; versionSpec: string} {
  if (spec.startsWith('@')) {
    let [_, name, versionSpec] = spec.split('@', 3);
    return {name: '@' + name, versionSpec};
  } else {
    let [name, versionSpec] = spec.split('@');
    return {name, versionSpec};
  }
}

function objectToDependencySpecList(...objs) {
  let dependencySpecList = [];
  for (let obj of objs) {
    if (obj == null) {
      continue;
    }
    for (let name in obj) {
      let versionSpec = obj[name];
      let dependencySpec = `${name}@${versionSpec}`;
      if (dependencySpecList.indexOf(dependencySpec) === -1) {
        dependencySpecList.push(dependencySpec);
      }
    }
  }
  return dependencySpecList;
}

function normalizeName(name) {
  return name
    .toLowerCase()
    .replace(/@/g, '')
    .replace(/\//g, '_')
    .replace(/\-/g, '_');
}

function packageInfoKey(env: Environment, packageInfo: PackageInfo) {
  let {packageJson: {name, version, esy}, normalizedName, source} = packageInfo;
  if (packageInfo.__cachedPackageHash == null) {
    let h = hash({
      env,
      source,
      packageInfo: {
        packageJson: {
          name, version, esy
        },
        dependencyTree: mapObject(packageInfo.dependencyTree, (dep: PackageInfo) =>
          packageInfoKey(env, dep)),
      },
    });
    if (process.env.ESY__TEST) {
      packageInfo.__cachedPackageHash = `${normalizedName}-${version || '0.0.0'}`;
    } else {
      packageInfo.__cachedPackageHash = `${normalizedName}-${version || '0.0.0'}-${h}`;
    }
  }
  return packageInfo.__cachedPackageHash;
}

function hash(value: mixed) {
  if (typeof value === 'object') {
    if (value === null) {
      return hash("null");
    } else if (!Array.isArray(value)) {
      const v = value;
      let keys = Object.keys(v);
      keys.sort();
      return hash(keys.map(k => [k, v[k]]));
    } else {
      return hash(JSON.stringify(value.map(hash)));
    }
  } else if (value === undefined) {
    return hash('undefined');
  } else {
    let hasher = crypto.createHash('sha1');
    hasher.update(JSON.stringify(value));
    return hasher.digest('hex');
  }
}

module.exports = {
  fromDirectory,
  traversePackageDependencyTree,
  collectTransitiveDependencies,
  packageInfoKey,
};
