const path = require('path');

function buildCommand(curDir, env, args) {

  // first group is a shared (built-in) env
  env = env.slice();
  let builtIns = env.shift();

  let envMap = env.reduce((envMap, pkg) => {
    envMap.set(pkg.packageJson.name, pkg);
    return envMap;
  }, new Map());

  let rules = env
    .map(pkg => generateMakeRule(builtIns, envMap, pkg))
    .filter(rule => rule != null);
  console.log(rules
    .map(rule => renderMakeRule(rule))
    .join('\n\n'));
}

function generateMakeRule(builtIns, envMap, pkg) {

  function envToEnvList(env) {
    return env.envVars.map(env => ({
      name: env.name,
      value: env.normalizedVal
    }));
  }

  if (pkg.packageJson.pjc && pkg.packageJson.pjc.build) {
    return {
      name: ` *** Build ${pkg.packageJson.name} ***`,
      target: pkg.packageJson.name,
      dependencies: pkg.packageJson.dependencies != null
        ? Object.keys(pkg.packageJson.dependencies)
        : [],
      env: []
        .concat(envToEnvList(builtIns))
        .concat(getBuildEnv(envMap, pkg))
        .concat(envToEnvList(pkg)),
      command: pkg.packageJson.pjc.build,
    };
  } else {
    // TODO: Returning an empty rule. Is that really what we want here?
    return {
      name: ` *** Build ${pkg.packageJson.name} ***`,
      target: pkg.packageJson.name,
      dependencies: pkg.packageJson.dependencies != null
        ? Object.keys(pkg.packageJson.dependencies)
        : [],
      command: null,
    };
  }
}

function getPkgEnv(envMap, pkg, current = false) {
  let prefix = current ? 'cur' : (pkg.packageJson.name + '_')
  let info = pkg.packageJson;
  return [
    {
      name: `${prefix}_name`,
      value: info.name,
    },
    {
      name: `${prefix}_version`,
      value: info.version,
    },
    {
      name: `${prefix}_root`,
      value: pkg.root,
    },
    {
      name: `${prefix}_depends`,
      value: info.dependencies != null
        ? `"${Object.keys(info.dependencies).join(' ')}"`
        : null,
    },
    {
      name: `${prefix}_depends_install_closed`,
      value: info.dependencies != null
      ? `"${collectTransitiveDependencies(envMap, info)
            .map(dep => `$_install_tree/node_modules/${dep}/lib`)
            .join(':')}"`
        : null,
    },
    {
      name: `${prefix}_target_dir`,
      value: `$_build_tree/node_modules/${info.name}`,
    },
    {
      name: `${prefix}_install`,
      value: `$_install_tree/node_modules/${info.name}/lib`,
    },
    {
      name: `${prefix}_bin`,
      value: `$_install_tree/${info.name}/bin`,
    },
    {
      name: `${prefix}_sbin`,
      value: `$_install_tree/${info.name}/sbin`,
    },
    {
      name: `${prefix}_lib`,
      value: `$_install_tree/${info.name}/lib`,
    },
    {
      name: `${prefix}_man`,
      value: `$_install_tree/${info.name}/man`,
    },
    {
      name: `${prefix}_doc`,
      value: `$_install_tree/${info.name}/doc`,
    },
    {
      name: `${prefix}_stublibs`,
      value: `$_install_tree/${info.name}/stublibs`,
    },
    {
      name: `${prefix}_toplevel`,
      value: `$_install_tree/${info.name}/toplevel`,
    },
    {
      name: `${prefix}_share`,
      value: `$_install_tree/${info.name}/share`,
    },
    {
      name: `${prefix}_etc`,
      value: `$_install_tree/${info.name}/etc`,
    },
  ];
}

function getBuildEnv(envMap, pkg, onlyMeta = false) {
  let info = pkg.packageJson;
  let name = info.name;
  let dependencies = info.dependencies != null
    ? Object.keys(info.dependencies)
    : [];
  let pkgEnv = [];
  if (!onlyMeta) {
    pkgEnv = pkgEnv.concat([
      {
        name: 'FINDLIB_CONF',
        value: null, // TODO
      },
      {
        name: 'sandbox',
        value: '$ESY__SANDBOX',
      },
      {
        name: '_install_tree',
        value: '$sandbox/_install',
      },
      {
        name: '_build_tree',
        value: '$sandbox/_build',
      },
    ]);

    pkgEnv = pkgEnv.concat(getPkgEnv(envMap, pkg, true));
  }

  pkgEnv = pkgEnv.concat(getPkgEnv(envMap, pkg, false));

  if (!onlyMeta && dependencies.length > 0) {
    pkgEnv = pkgEnv.concat(
      ...dependencies.map(dep => getBuildEnv(envMap, envMap.get(dep), true))
    );
    let depPath = dependencies.map(dep => `$_install_tree/${dep}/bin`).join(':');
    let depManPath = dependencies.map(dep => `$_install_tree/${dep}/man`).join(':');
    pkgEnv = pkgEnv.concat([
      {
        name: 'PATH',
        value: `${depPath}:$PATH`,
      },
      {
        name: 'MAN_PATH',
        value: `${depManPath}:$MAN_PATH`,
      }
    ]);
  }
  return pkgEnv;
}

function collectTransitiveDependencies(envMap, info) {
  if (info.dependencies == null) {
    return [];
  } else {
    let dependencies = Object.keys(info.dependencies);
    let set = new Set(dependencies);
    for (let dep of dependencies) {
      let depInfo = envMap.get(dep).packageJson;
      for (let subdep of collectTransitiveDependencies(envMap, depInfo)) {
        set.add(subdep);
      }
    }
    return [...set];
  }
}

function renderMakeRule(rule) {
  let header = `${rule.target}: ${rule.dependencies.join(' ')}`;
  if (rule.command != null) {
    let recipe = renderMakeRuleCommand(rule.env, rule.command);
    recipe = recipe.replace(/\$/g, '\$\$\$');
    return `${header}\n\t@echo '${rule.name}'\n\t@${recipe}`;
  } else {
    return header;
  }
}

function renderMakeRuleCommand(env, command) {
  if (env.length > 0) {
    let renderedEnv = env
      .filter(env => env.value != null)
      .map(env => `export ${env.name}=${env.value}; \\`)
      .join('\n\t');
    return `${renderedEnv}\n\t${command}`;
  } else {
    return command;
  }
}

module.exports = buildCommand;
