/**
 * @flow
 */

import type {
  PackageDb,
  PackageJson,
  EnvironmentVarExport
} from './PackageDb';

const path = require('path');
const pathIsInside = require('path-is-inside');
const fs = require('fs');
const os = require('os');
const {
  traversePackageDb,
  collectDependencies,
} = require('./PackageDb');

export type EnvironmentVar = {
  name: string;
  value: ?string;
  automaticDefault?: boolean;
};

export type EnvironmentGroup = {
  packageJsonPath: string;
  packageJson: PackageJson;
  envVars: Array<EnvironmentVar>;
  errors: Array<string>;
};

export type Environment = Array<EnvironmentGroup>;

// X platform newline
const EOL = os.EOL;
const delim = path.delimiter;

let globalGroups = [];
let globalSeenVars = {};

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
function relativeToSandbox(realFromPath, toPath) {
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
  let toPathToUse = pathIsInside(realFromPath, realToPath)
    ? realToPath
    : toPath;
  let ret = path.relative(realFromPath, toPathToUse);
  return (ret == '0') ? "$esy__sandbox" : path.join("$esy__sandbox", ret);
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

function builtInsPerPackage(
  packageDb,
  prefix,
  packageName
) {
  let {
    packageJson,
    packageJsonFilePath
  } = packageDb.packagesByName[packageName];
  let packageRoot = path.dirname(packageJsonFilePath);
  let isRootPackage = packageJson.name === packageDb.rootPackageName;
  function builtIn(val) {
    return {
      __BUILT_IN_DO_NOT_USE_OR_YOU_WILL_BE_PIPd: true,
      global: false,
      exclusive: true,
      val,
    }
  }
  return {
    [`${prefix}__name`]: builtIn(
      packageJson.name
    ),
    [`${prefix}__version`]: builtIn(
      packageJson.version || null
    ),
    [`${prefix}__root`]: builtIn(
      relativeToSandbox(packageDb.path, packageRoot)
    ),
    [`${prefix}__depends`]: builtIn(
      collectDependencies(packageDb, packageName).join(' ')
    ),
    [`${prefix}__target_dir`]: builtIn(
      isRootPackage
        ? `$esy__build_tree`
        : `$esy__build_tree/node_modules/${packageJson.name}`
    ),
    [`${prefix}__install`]: builtIn(
      isRootPackage
        ? `$esy__install_tree`
        : `$esy__install_tree/node_modules/${packageJson.name}`
    ),
    [`${prefix}__bin`]: builtIn(
      `$${prefix}__install/bin`
    ),
    [`${prefix}__sbin`]: builtIn(
      `$${prefix}__install/sbin`
    ),
    [`${prefix}__lib`]: builtIn(
      `$${prefix}__install/lib`
    ),
    [`${prefix}__man`]: builtIn(
      `$${prefix}__install/man`
    ),
    [`${prefix}__doc`]: builtIn(
      `$${prefix}__install/doc`
    ),
    [`${prefix}__stublibs`]: builtIn(
      `$${prefix}__install/stublibs`
    ),
    [`${prefix}__toplevel`]: builtIn(
      `$${prefix}__install/toplevel`
    ),
    [`${prefix}__share`]: builtIn(
      `$${prefix}__install/share`
    ),
    [`${prefix}__etc`]: builtIn(
      `$${prefix}__install/etc`
    ),
  };
}

function addEnvConfigForPackage(
  seenVars,
  errors,
  normalizedEnvVars,
  realPathSandboxRootOnEjectingHost,
  packageName,
  packageJsonFilePath,
  exportedEnvVars
) {
  var nextSeenVars = {};
  var nextErrors = []
  var nextNormalizedEnvVars = [];
  for (var envVar in exportedEnvVars) {
    var config = exportedEnvVars[envVar];
    nextNormalizedEnvVars.push({
      name: envVar,
      value: config.val,
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
    nextSeenVars[envVar] = {
      packageJsonPath: packageJsonFilePath || 'unknownPackage',
      config
    };
  }
  return {
    errors: errors.concat(nextErrors),
    seenVars: extend(seenVars, nextSeenVars),
    normalizedEnvVars: normalizedEnvVars.concat(nextNormalizedEnvVars)
  };
}

function computeEnvVarsForPackage(
  packageDb,
  {packageJsonFilePath, packageJson, normalizedName}
) {
  var packageJsonDir = path.dirname(packageJsonFilePath);
  var envPaths = packageJson.exportedEnvVars;
  var packageName = packageJson.name;
  var envVarConfigPrefix = normalizedName;
  let errors = [];
  var autoExportedEnvVarsForPackage = builtInsPerPackage(
    packageDb,
    envVarConfigPrefix,
    packageJson.name
  );
  let {
    seenVars,
    errors: nextErrors,
    normalizedEnvVars
  } = addEnvConfigForPackage(
    globalSeenVars,
    errors,
    [],
    packageDb.path,
    packageName,
    packageJsonFilePath,
    autoExportedEnvVarsForPackage
  );

  for (var envVar in packageJson.exportedEnvVars) {
    nextErrors = nextErrors.concat(
      validatePackageJsonExportedEnvVar(
        envVar,
        packageJson.exportedEnvVars[envVar],
        packageName,
        envVarConfigPrefix
      )
    );
  }

  let {
    seenVars: nextSeenVars,
    errors: nextNextErrors,
    normalizedEnvVars: nextNormalizedEnvVars
  } = addEnvConfigForPackage(
    seenVars,
    nextErrors,
    normalizedEnvVars,
    packageDb.path,
    packageName,
    packageJsonFilePath,
    packageJson.exportedEnvVars
  );

  /**
   * Update the global. Yes, we tried to be as functional as possible aside
   * from this.
   */
  globalSeenVars = nextSeenVars;
  globalGroups.push({
    root: relativeToSandbox(
      packageDb.path,
      path.dirname(packageJsonFilePath)
    ),
    packageJsonPath: relativeToSandbox(
      packageDb.path,
      packageJsonFilePath
    ),
    packageJson: packageJson,
    envVars: nextNormalizedEnvVars,
    errors: nextNextErrors
  })
}

/**
 * For a given package name within the package database, compute the environment
 * variable setup in terms of a hypothetical root.
 */
function calculateEnvironment(
  packageDb: PackageDb,
  currentlyBuildingPackageName: string
): Environment {
  /**
   * The root package.json path on the "ejecting host" - that is, the host where
   * the universal build script is being computed. Everything else should be
   * relative to this.
   */
  let curRootPackageJsonOnEjectingHost = packageDb.packagesByName[currentlyBuildingPackageName].packageJsonFilePath;
  let currentlyBuildingPackageRoot = path.dirname(curRootPackageJsonOnEjectingHost);
  globalSeenVars = {};

  function setUpBuiltinVariables(seenVars, errors, normalizedEnvVars) {
    let sandboxExportedEnvVars: {[name: string]: EnvironmentVarExport} = Object.assign(
      {
        'esy__sandbox': {
          val: '$ESY__SANDBOX',
          exclusive: true,
          __BUILT_IN_DO_NOT_USE_OR_YOU_WILL_BE_PIPd: true,
        },
        'esy__install_tree': {
          val: '$esy__sandbox/_install',
          exclusive: true,
          __BUILT_IN_DO_NOT_USE_OR_YOU_WILL_BE_PIPd: true,
        },
        'esy__build_tree': {
          val: '$esy__sandbox/_build',
          exclusive: true,
          __BUILT_IN_DO_NOT_USE_OR_YOU_WILL_BE_PIPd: true,
        },
      },
      builtInsPerPackage(packageDb, 'cur', currentlyBuildingPackageName),
      {
        'OCAMLFIND_CONF': {
          val: '$cur__target_dir/findlib.conf',
          exclusive: false
        },
      }
    );

    let dependencies = collectDependencies(packageDb, currentlyBuildingPackageName);
    if (dependencies.length > 0) {
      let depPath = dependencies
        .map(dep => `$esy__install_tree/node_modules/${dep}/bin`)
        .join(':');
      let depManPath = dependencies
        .map(dep => `$esy__install_tree/node_modules/${dep}/man`)
        .join(':');
      sandboxExportedEnvVars = Object.assign(sandboxExportedEnvVars, {
        'PATH': {
          val: `${depPath}:$PATH`,
          exclusive: false,
        },
        'MAN_PATH': {
          val: `${depManPath}:$MAN_PATH`,
          exclusive: false,
        }
      });
    }

    let {
      seenVars: nextSeenVars,
      errors: nextErrors,
      normalizedEnvVars: nextNormalizedEnvVars
    } = addEnvConfigForPackage(
      seenVars,
      errors,
      normalizedEnvVars,
      packageDb.path,
      "EsySandBox",
      curRootPackageJsonOnEjectingHost,
      sandboxExportedEnvVars
    );
    let {
      seenVars: nextNextSeenVars,
      errors: nextNextErrors,
      normalizedEnvVars: nextNextNormalizedEnvVars,
    } = addEnvConfigForPackage(
      nextSeenVars,
      nextErrors,
      nextNormalizedEnvVars,
      packageDb.path,
      "EsySandBox",
      curRootPackageJsonOnEjectingHost,
      {}
    );
    return {
      seenVars: nextNextSeenVars,
      errors: nextNextErrors,
      normalizedEnvVars: nextNextNormalizedEnvVars
    };
  }

  try {
    let {
      seenVars,
      errors,
      normalizedEnvVars
    } = setUpBuiltinVariables(globalSeenVars, [], []);

    /**
     * Update the global. Sadly, haven't thread it through the
     * traversePackageTree.
     */
    globalSeenVars = seenVars;
    globalGroups = [{
      packageJsonPath: curRootPackageJsonOnEjectingHost,
      packageJson: {name: "EsySandboxVariables"},
      envVars: normalizedEnvVars,
      errors: errors
    }];
    traversePackageDb(
      packageDb,
      computeEnvVarsForPackage.bind(null, packageDb),
      currentlyBuildingPackageName
    );
  } catch (err) {
    if (err.code === 'ENOENT') {
      console.error("Fail to find package.json!: " + err.message);
    } else {
      throw err;
    }
  }

  var ret = globalGroups;

  globalGroups = [];
  globalSeenVars = {};

  return ret;
};

function printEnvironment(groups: Environment) {
  return groups.map(function(group) {
    let headerLines = [
      '',
      '# ' + group.packageJson.name + (group.packageJson.version ? '@' + (group.packageJson.version) : '') + ' ' +  group.packageJsonPath ,
    ];
    let renderingBuiltInsForGroup = false;
    let errorLines = group.errors.map(err => {
      return '# [ERROR] ' + err
    });
    let envVarLines = group.envVars
      .map(envVar => {
        if (envVar.value == null) {
          return null;
        }
        let exportLine = `export ${envVar.name}="${envVar.value}"`;
        if (!renderingBuiltInsForGroup && envVar.automaticDefault) {
          renderingBuiltInsForGroup = true;
          return ['# [BuiltIns]', exportLine ].join(EOL);
        } else if (renderingBuiltInsForGroup && !envVar.automaticDefault) {
          renderingBuiltInsForGroup = false;
          return ['# [Custom Variables]', exportLine ].join(EOL);
        } else {
          return exportLine;
        }
      })
      .filter(envVar => envVar != null);
    return headerLines.concat(errorLines).concat(envVarLines).join(EOL);
  }).join(EOL);
};

module.exports = {
  calculateEnvironment,
  printEnvironment,
};

/**
 * TODO: Cache this result on disk in a .reasonLoadEnvCache so that we don't
 * have to repeat this process.
 */
