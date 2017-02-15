'use strict';

var _extends = Object.assign || function (target) { for (var i = 1; i < arguments.length; i++) { var source = arguments[i]; for (var key in source) { if (Object.prototype.hasOwnProperty.call(source, key)) { target[key] = source[key]; } } } return target; };

let resolve = (() => {
  var _ref = _asyncToGenerator(function* (packageName, baseDirectory) {
    return new Promise(function (resolve, reject) {
      resolveBase(packageName, { basedir: baseDirectory }, function (err, resolution) {
        if (err) {
          reject(err);
        } else {
          resolve(resolution);
        }
      });
    });
  });

  return function resolve(_x, _x2) {
    return _ref.apply(this, arguments);
  };
})();

let resolveToRealpath = (() => {
  var _ref2 = _asyncToGenerator(function* (packageName, baseDirectory) {
    let resolution = yield resolve(packageName, baseDirectory);
    return fs.realpath(resolution);
  });

  return function resolveToRealpath(_x3, _x4) {
    return _ref2.apply(this, arguments);
  };
})();

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


/**
 * Sandbox build environment is a set of k-v pairs.
 */


let fromDirectory = (() => {
  var _ref3 = _asyncToGenerator(function* (directory) {
    const source = path.resolve(directory);
    const env = getEnvironment();
    const looseEnv = _extends({}, env);
    delete looseEnv.PATH;
    delete looseEnv.SHELL;
    const packageJson = yield readPackageJson(path.join(directory, 'package.json'));
    const depSpecList = objectToDependencySpecList(packageJson.dependencies, packageJson.peerDependencies);

    if (depSpecList.length > 0) {
      let resolveWithCache = (() => {
        var _ref4 = _asyncToGenerator(function* (packageName, baseDir) {
          let key = `${baseDir}__${packageName}`;
          let resolution = resolveCache.get(key);
          if (resolution == null) {
            resolution = resolveToRealpath(packageName, baseDir);
            resolveCache.set(key, resolution);
          }
          return resolution;
        });

        return function resolveWithCache(_x6, _x7) {
          return _ref4.apply(this, arguments);
        };
      })();

      let buildPackageInfoWithCache = (() => {
        var _ref5 = _asyncToGenerator(function* (baseDirectory, context) {
          let packageInfo = packageInfoCache.get(baseDirectory);
          if (packageInfo == null) {
            packageInfo = buildPackageInfo(baseDirectory, context);
            packageInfoCache.set(baseDirectory, packageInfo);
          }
          return packageInfo;
        });

        return function buildPackageInfoWithCache(_x8, _x9) {
          return _ref5.apply(this, arguments);
        };
      })();

      const resolveCache = new Map();

      const packageInfoCache = new Map();

      const [dependencyTree, errors] = yield buildDependencyTree(source, depSpecList, {
        resolve: resolveWithCache,
        buildPackageInfo: buildPackageInfoWithCache,
        packageDependencyTrace: [packageJson.name]
      });

      return {
        env,
        looseEnv,
        packageInfo: {
          source: `local:${yield fs.realpath(source)}`,
          sourceType: 'local',
          normalizedName: normalizeName(packageJson.name),
          rootDirectory: source,
          packageJson,
          dependencyTree,
          errors
        }
      };
    } else {
      return {
        env,
        looseEnv,
        packageInfo: {
          source: `local:${yield fs.realpath(source)}`,
          sourceType: 'local',
          normalizedName: normalizeName(packageJson.name),
          rootDirectory: source,
          packageJson,
          dependencyTree: {},
          errors: []
        }
      };
    }
  });

  return function fromDirectory(_x5) {
    return _ref3.apply(this, arguments);
  };
})();

/**
 * Traverse package dependency tree.
 */


let buildDependencyTree = (() => {
  var _ref6 = _asyncToGenerator(function* (baseDir, dependencySpecList, context) {
    let dependencyTree = {};
    let errors = [];
    let missingPackages = [];

    for (let dependencySpec of dependencySpecList) {
      const { name } = parseDependencySpec(dependencySpec);

      if (context.packageDependencyTrace.indexOf(name) > -1) {
        errors.push({
          message: formatCircularDependenciesError(name, context)
        });
        continue;
      }

      let dependencyPackageJsonPath = '/does/not/exists';
      try {
        dependencyPackageJsonPath = yield context.resolve(`${name}/package.json`, baseDir);
      } catch (_err) {
        missingPackages.push(name);
        continue;
      }

      const packageInfo = yield context.buildPackageInfo(dependencyPackageJsonPath, context);

      errors = errors.concat(packageInfo.errors);
      dependencyTree[name] = packageInfo;
    }

    if (missingPackages.length > 0) {
      errors.push({
        message: formatMissingPackagesError(missingPackages, context)
      });
    }

    return [dependencyTree, errors];
  });

  return function buildDependencyTree(_x10, _x11, _x12) {
    return _ref6.apply(this, arguments);
  };
})();

let buildPackageInfo = (() => {
  var _ref7 = _asyncToGenerator(function* (baseDirectory, context) {
    const dependencyBaseDir = path.dirname(baseDirectory);
    const packageJson = yield readPackageJson(baseDirectory);
    const [packageDependencyTree, packageErrors] = yield buildDependencyTree(dependencyBaseDir, objectToDependencySpecList(packageJson.dependencies, packageJson.peerDependencies), _extends({}, context, {
      packageDependencyTrace: context.packageDependencyTrace.concat(packageJson.name)
    }));
    return {
      errors: packageErrors,
      version: packageJson.version,
      source: packageJson._resolved || `local:${yield fs.realpath(dependencyBaseDir)}`,
      sourceType: packageJson._resolved ? 'remote' : 'local',
      rootDirectory: dependencyBaseDir,
      packageJson,
      normalizedName: normalizeName(packageJson.name),
      dependencyTree: packageDependencyTree
    };
  });

  return function buildPackageInfo(_x13, _x14) {
    return _ref7.apply(this, arguments);
  };
})();

let readJson = (() => {
  var _ref8 = _asyncToGenerator(function* (filename) {
    const data = yield fs.readFile(filename, 'utf8');
    return JSON.parse(data);
  });

  return function readJson(_x15) {
    return _ref8.apply(this, arguments);
  };
})();

let readPackageJson = (() => {
  var _ref9 = _asyncToGenerator(function* (filename) {
    const packageJson = yield readJson(filename);
    if (packageJson.esy == null) {
      packageJson.esy = {
        build: null,
        exportedEnv: {},
        buildsInSource: false
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
  });

  return function readPackageJson(_x16) {
    return _ref9.apply(this, arguments);
  };
})();

function _asyncToGenerator(fn) { return function () { var gen = fn.apply(this, arguments); return new Promise(function (resolve, reject) { function step(key, arg) { try { var info = gen[key](arg); var value = info.value; } catch (error) { reject(error); return; } if (info.done) { resolve(value); } else { return Promise.resolve(value).then(function (value) { step("next", value); }, function (err) { step("throw", err); }); } } return step("next"); }); }; }

const crypto = require('crypto');
const fs = require('mz/fs');
const path = require('path');
const outdent = require('outdent');
const resolveBase = require('resolve');
const { mapObject } = require('./Utility');

function traversePackageDependencyTree(packageInfo, handler) {
  let seen = new Set();
  traversePackageDependencyTreeImpl(packageInfo, seen, handler);
}

function traversePackageDependencyTreeImpl(packageInfo, seen, handler) {
  let { dependencyTree } = packageInfo;
  for (let dependencyName in dependencyTree) {
    if (seen.has(dependencyName)) {
      continue;
    }
    seen.add(dependencyName);
    traversePackageDependencyTreeImpl(dependencyTree[dependencyName], seen, handler);
  }
  handler(packageInfo);
}

function collectTransitiveDependencies(packageInfo, seen = new Set()) {
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
    'esy__target_architecture': architecture
  };
}

function formatMissingPackagesError(missingPackages, context) {
  let packagesToReport = missingPackages.slice(0, 3);
  let packagesMessage = packagesToReport.map(p => `"${p}"`).join(', ');
  let extraPackagesMessage = missingPackages.length > packagesToReport.length ? ` (and ${missingPackages.length - packagesToReport.length} more)` : '';
  return outdent`
    Cannot resolve ${packagesMessage}${extraPackagesMessage} packages
      At ${context.packageDependencyTrace.join(' -> ')}
      Did you forget to run "esy install" command?
  `;
}

function formatCircularDependenciesError(dependency, context) {
  return outdent`
    Circular dependency "${dependency} detected
      At ${context.packageDependencyTrace.join(' -> ')}
  `;
}

function parseDependencySpec(spec) {
  if (spec.startsWith('@')) {
    let [_, name, versionSpec] = spec.split('@', 3);
    return { name: '@' + name, versionSpec };
  } else {
    let [name, versionSpec] = spec.split('@');
    return { name, versionSpec };
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
  return name.toLowerCase().replace(/@/g, '').replace(/\//g, '_').replace(/\-/g, '_');
}

function packageInfoKey(env, packageInfo) {
  let { packageJson: { name, version, esy }, normalizedName, source } = packageInfo;
  if (packageInfo.__cachedPackageHash == null) {
    let h = hash({
      env,
      source,
      packageInfo: {
        packageJson: {
          name, version, esy
        },
        dependencyTree: mapObject(packageInfo.dependencyTree, dep => packageInfoKey(env, dep))
      }
    });
    if (process.env.ESY__TEST) {
      packageInfo.__cachedPackageHash = `${normalizedName}-${version || '0.0.0'}`;
    } else {
      packageInfo.__cachedPackageHash = `${normalizedName}-${version || '0.0.0'}-${h}`;
    }
  }
  return packageInfo.__cachedPackageHash;
}

function hash(value) {
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
  packageInfoKey
};
