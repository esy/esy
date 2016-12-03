#!/usr/bin/env node

var path = require('path');
var pathIsInside = require('path-is-inside');
var resolve = require('resolve');
var path = require('path');
var fs = require('fs');
var os = require('os');
// X platform newline
var EOL = os.EOL;
var delim = path.delimiter;
const KEYS = [
  'dependencies',
  'peerDependencies',
];
var globalGroups = [];
var globalVisitedRealPaths = {};
var globalSeenVars = {};

function extend(o, more) {
  var next = {};
  for (var key in o) {
    next[key]= o[key];
  }
  for (var key in more) {
    next[key]= more[key];
  }
  return next;
}

/**
 * Ejects a path for the sake of printing to a shell script/Makefile to be
 * executed on a different host. We therefore print it relative to an abstract
 * and not-yet-assigned $ESY__SANDBOX.
 *
 * This is the use case:
 *
 * 0. Run npm install.
 * 1. Don't build.
 * 3. Generate shell script/makefile.
 * 4. tar the entire directory with the --dereference flag.
 * 5. scp it to a host where node isn't even installed.
 * 6. untar it with the -h flag.
 *
 * All internal symlinks will be preserved. I *believe* --dereference will copy
 * contents if symlink points out of the root location (I hope).
 *
 * So our goal is to ensure that the locations we record point to the realpath
 * if a location is actually a symlink to somewhere in the sandbox, but encode
 * the path (including symlinks) if it points outside the sandbox.  I believe
 * that will work with tar --dereference.
 */
let relativeToSandbox = (realFromPath, toPath) => {
  /**
   * This sucks. If there's a symlink pointing outside of the sandbox, the
   * script can't include those, so it gives it from perspective of symlink.
   * This will work with tar, but there could be issues if multiple symlink
   * links all point to the same location, but appear to be different.  We
   * should execute a warning here instead. This problem is far from solved.
   * What would tar even do in that situation if it's following symlinks
   * outside of the tar directory? Would it copy it multiple times or copy it
   * once somehow?
   */
  let realToPath = fs.realpathSync(toPath);
  let toPathToUse =
    pathIsInside(realFromPath, realToPath) ? realToPath : toPath;
  let ret = path.relative(realFromPath, toPathToUse);
  return (ret == 0) ? "$ESY__SANDBOX" : path.join("$ESY__SANDBOX", ret);
};

function resolveDep(dependency, basedir) {
  try {
    return resolve.sync(
      path.join(dependency, 'package.json'),
      {basedir: dir}
    );
  } catch (err) { }
  throw "cannot find " + dependency + " in " + dirs;
}

function traverseSync(packageJsonPathOnEjectingHost, handler) {
  const packageJsonPathOnEjectingHostRealPath = fs.realpathSync(packageJsonPathOnEjectingHost);
  const pkg = JSON.parse(fs.readFileSync(packageJsonPathOnEjectingHost, 'utf8'));
  if (!pkg.name) {
    throw ("no package name for package:" + packageJsonPathOnEjectingHost);
  }
  globalVisitedRealPaths[pkg.name] = packageJsonPathOnEjectingHostRealPath;
  /**
   * How about the convention that `buildTimeOnlyDependencies` won't be
   * traversed transitively to compute environments. The primary use case is
   * that we generally only need a binary produced - or a dll.
   */
  KEYS.forEach(function(key) {
    Object.keys(
      pkg[key] || {}
    ).forEach(function(dependencyName) {
        try {
          const resolved = resolve.sync(
            path.join(dependencyName, 'package.json'),
            {basedir: path.dirname(packageJsonPathOnEjectingHost)}
          );
          if (!globalVisitedRealPaths[dependencyName]) {
            traverseSync(resolved, handler);
          } else {
            if (globalVisitedRealPaths[dependencyName] !== fs.realpathSync(resolved)) {
              // Find a way to aggregate warnings.
              // console.warn(
              //   "While computing environment for " + pkg.name + ", found that there are two separate packages named " +
              //     dependencyName + " at two different real paths on disk. One is at " +
              //     globalVisitedRealPaths[dependencyName] + " and the other at " + fs.realpathSync(resolved)
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
    });
  });
  handler(packageJsonPathOnEjectingHost, pkg);
}

function getScopes(config) {
  if (!config.scope) {
    return {};
  }
  var scopes = (config.scope || '').split('|');
  var scopeObj = {};
  for (var i = 0; i < scopes.length; i++) {
    scopeObj[scopes[i]] = true;
  }
  return scopeObj;
}

/**
 * Validates env vars that were configured in package.json as opposed to
 * automatically created.
 */
var validatePackageJsonExportedEnvVar = (envVar, config, inPackageName, envVarConfigPrefix) => {
  let beginsWithPackagePrefix = envVar.indexOf(envVarConfigPrefix) === 0;
  var ret = [];
  if (config.scopes !== undefined) {
    ret.push(
         envVar + " has a field 'scopes' (plural). You probably meant 'scope'. " +
        "The owner of " + inPackageName + " likely made a mistake"
    );
  }
  let scopeObj = getScopes(config);
  if (!scopeObj.global) {
    if (!beginsWithPackagePrefix) {
      if (envVar.toUpperCase().indexOf(envVarConfigPrefix) === 0) {
        ret.push(
            "It looks like " + envVar + " is trying to be configured as a package scoped variable, " +
            "but it has the wrong capitalization. It should begin with " + envVarConfigPrefix +
            ". The owner of " + inPackageName + " likely made a mistake"
        );
      } else {
        ret.push(
          "Environment variable " + envVar + " " +
            "doesn't begin with " + envVarConfigPrefix + " but it is not marked as 'global'. " +
            "You should either prefix variables with " + envVarConfigPrefix + " or make them global." +
            "The author of " + inPackageName + " likely made a mistake"
        );
      }
    }
  } else {
    // Else, it's global, but better not be trying to step on another package!
    if (!beginsWithPackagePrefix && envVar.indexOf("__") !== -1) {
      ret.push(
        envVar +
          " looks like it's trying to step on another " +
          "package because it has a double underscore - which is how we express namespaced env vars. " +
          "The package owner for " + inPackageName + " likely made a mistake"
      );
    }
  }
  return ret;
};


var builtInsPerPackage = (realPathSandboxRootOnEjectingHost, envVarPrefix, packageRoot) => {
  var autoExportedEnvVars = {};
  autoExportedEnvVars[envVarPrefix + 'ROOT'] =  {
    __BUILT_IN_DO_NOT_USE_OR_YOU_WILL_BE_PIPd: true,
    global: false,
    val: relativeToSandbox(realPathSandboxRootOnEjectingHost, packageRoot),
    exclusive: true,
  };
  return autoExportedEnvVars;
};

function addEnvConfigForPackage(seenVars, errors, normalizedEnvVars, realPathSandboxRootOnEjectingHost, packageName, packageJsonFilePath, exportedEnvVars) {
  var nextSeenVars = {};
  var nextErrors = []
  var nextNormalizedEnvVars = [];
  for (var envVar in exportedEnvVars) {
    var config = exportedEnvVars[envVar];
    nextNormalizedEnvVars.push({
      name: envVar,
      normalizedVal: config.val,
      automaticDefault: !!config.__BUILT_IN_DO_NOT_USE_OR_YOU_WILL_BE_PIPd
    })
    // The seenVars will only cover the cases when another package declares the
    // variable, not when it's loaded from your bashrc etc.
    if (seenVars[envVar] && seenVars[envVar].config.exclusive) {
      nextErrors.push(
        (seenVars[envVar].config.__BUILT_IN_DO_NOT_USE_OR_YOU_WILL_BE_PIPd ? 'Built-in variable ' : '') +
        envVar +
          " has already been set by " + relativeToSandbox(realPathSandboxRootOnEjectingHost, seenVars[envVar].packageJsonPath) + " " +
          "which configured it with exclusive:true. That means it wants to be the only one to set it. Yet " +
          packageName + " is trying to override it."
      );
    }
    if (seenVars[envVar] && (config.exclusive)) {
      nextErrors.push(
        envVar +
          " has already been set by " + relativeToSandbox(realPathSandboxRootOnEjectingHost, seenVars[envVar].packageJsonPath) + " " +
          "and " + packageName + " has configured it with exclusive:true. " +
          "Sometimes you can reduce the likehood of conflicts by marking some packages as buildTimeOnlyDependencies."
      );
    }
    nextSeenVars[envVar] = {packageJsonPath: packageJsonFilePath || 'unknownPackage', config};
  }
  return {errors: errors.concat(nextErrors), seenVars: extend(seenVars, nextSeenVars), normalizedEnvVars: normalizedEnvVars.concat(nextNormalizedEnvVars)};
}

function computeEnvVarsForPackage(realPathSandboxRootOnEjectingHost, packageJsonFilePath, packageJson) {
  var packageJsonDir = path.dirname(packageJsonFilePath);
  var envPaths = packageJson.exportedEnvVars;
  var packageName = packageJson.name;
  var envVarConfigPrefix =
    (packageName.replace(new RegExp("\-", "g"), function(s){return "_";}) + "__").toUpperCase();
  let errors = [];
  var autoExportedEnvVarsForPackage = builtInsPerPackage(realPathSandboxRootOnEjectingHost, envVarConfigPrefix, path.dirname(packageJsonFilePath));
  let {seenVars, errors: nextErrors, normalizedEnvVars} =
    addEnvConfigForPackage(globalSeenVars, errors, [], realPathSandboxRootOnEjectingHost, packageName, packageJsonFilePath, autoExportedEnvVarsForPackage)

  for (var envVar in packageJson.exportedEnvVars) {
    nextErrors = nextErrors.concat(validatePackageJsonExportedEnvVar(envVar, packageJson.exportedEnvVars[envVar], packageName, envVarConfigPrefix));
  }
  let {seenVars: nextSeenVars, errors: nextNextErrors, normalizedEnvVars: nextNormalizedEnvVars} =
    addEnvConfigForPackage(seenVars, nextErrors, normalizedEnvVars, realPathSandboxRootOnEjectingHost, packageName, packageJsonFilePath, packageJson.exportedEnvVars)

  /**
   * Update the global. Yes, we tried to be as functional as possible aside
   * from this.
   */
  globalSeenVars = nextSeenVars;
  globalGroups.push({
    root: relativeToSandbox(
      realPathSandboxRootOnEjectingHost,
      path.dirname(packageJsonFilePath)
    ),
    packageJsonPath: relativeToSandbox(
      realPathSandboxRootOnEjectingHost,
      packageJsonFilePath
    ),
    packageJson: packageJson,
    envVars: nextNormalizedEnvVars,
    errors: nextNextErrors
  })
}


/**
 * For a given *real* physical, absolute path on *this* host
 * (`realPathSandboxRootOnEjectingHost`), compute the environment
 * variable setup in terms of a hypothetical root
 * `ESY_DYNAMICALLY_SET_ME_TO_SANDBOX_ROOT_ON_HOST`
 */
exports.getRelativizedEnv = (realPathSandboxRootOnEjectingHost, currentlyBuildingPackageRoot) => {
  /**
   * The root package.json path on the "ejecting host" - that is, the host where
   * the universal build script is being computed. Everything else should be
   * relative to this.
   */
  var curRootPackageJsonOnEjectingHost = path.join(realPathSandboxRootOnEjectingHost, 'package.json');
  globalVisitedRealPaths = {};
  globalSeenVars = {};
  function setUpBuiltinVariables(seenVars, errors, normalizedEnvVars) {
    var sandboxExportedEnvVars = {
      ESY__SANDBOX: {
        __BUILT_IN_DO_NOT_USE_OR_YOU_WILL_BE_PIPd: true,
        global: true,
        val: "$ESY_DYNAMICALLY_SET_ME_TO_SANDBOX_ROOT_ON_HOST",
        exclusive: true
      }
    };
    let {seenVars: nextSeenVars, errors:nextErrors, normalizedEnvVars:nextNormalizedEnvVars} =
      addEnvConfigForPackage(seenVars, errors, normalizedEnvVars, realPathSandboxRootOnEjectingHost, "EsySandBox", curRootPackageJsonOnEjectingHost, sandboxExportedEnvVars);
    var currentlyBuildingExportedEnvVars = builtInsPerPackage(realPathSandboxRootOnEjectingHost, 'CUR__', currentlyBuildingPackageRoot);
    let {seenVars: nextNextSeenVars, errors:nextNextErrors, normalizedEnvVars: nextNextNormalizedEnvVars} =
      addEnvConfigForPackage(nextSeenVars, nextErrors, nextNormalizedEnvVars, realPathSandboxRootOnEjectingHost, "EsySandBox", curRootPackageJsonOnEjectingHost, currentlyBuildingExportedEnvVars)
    return {seenVars: nextNextSeenVars, errors: nextNextErrors, normalizedEnvVars: nextNextNormalizedEnvVars};
  }
  try {
    let {seenVars, errors, normalizedEnvVars} = setUpBuiltinVariables(globalSeenVars, [], []);

    /**
     * Update the global. Sadly, haven't thread it through the traverseSync.
     */
    globalSeenVars = seenVars;
    globalGroups = [{
      packageJsonPath: curRootPackageJsonOnEjectingHost,
      packageJson: {name: "EsySandboxVariables"},
      envVars: normalizedEnvVars,
      errors: errors
    }];
    traverseSync(curRootPackageJsonOnEjectingHost, computeEnvVarsForPackage.bind(null, realPathSandboxRootOnEjectingHost));
  } catch (err) {
    if (err.code === 'ENOENT') {
      console.error("Fail to find package.json!: " + err.message);
    } else {
      throw err;
    }
  }

  var ret = globalGroups;
  globalGroups = [];
  errors = [];
  globalVisitedRealPaths = {};
  globalSeenVars = {};
  return ret;
};

exports.print = (groups) => {
  return groups.map(function(group) {
    let headerLines = [
      '',
      '# ' + group.packageJson.name + (group.packageJson.version ? '@' + (group.packageJson.version) : '') + ' ' +  group.packageJsonPath ,
    ];
    let renderingBuiltInsForGroup = false;
    let errorLines = group.errors.map(err => {
      return '# [ERROR] ' + err
    });
    let envVarLines =
      group.envVars.map(envVar => {
        let exportLine = 'export ' + envVar.name + '=' + envVar.normalizedVal;
        if (!renderingBuiltInsForGroup && envVar.automaticDefault) {
          renderingBuiltInsForGroup = true;
          return ['# [BuiltIns]', exportLine ].join(EOL);
        } else if (renderingBuiltInsForGroup && !envVar.automaticDefault) {
          renderingBuiltInsForGroup = false;
          return ['# [Custom Variables]', exportLine ].join(EOL);
        } else {
          return exportLine;
        }
      });
    return headerLines.concat(errorLines).concat(envVarLines).join(EOL);
  }).join(EOL);
};

exports.loadIntoProcess = (groups) => {

};


/**
 * TODO: Cache this result on disk in a .reasonLoadEnvCache so that we don't
 * have to repeat this process.
 */

