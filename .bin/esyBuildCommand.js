const childProcess = require('child_process');
const path = require('path');

const ESY_SANDBOX_REF = '$(ESY__SANDBOX)';

function installDir(pkgName, ...args) {
  return path.join(
    '$(ESY__SANDBOX)', '_install', 'node_modules', pkgName, ...args);
}

function buildDir(pkgName, ...args) {
  return path.join(
    '$(ESY__SANDBOX)', '_build', 'node_modules', pkgName, ...args);
}

function envToEnvList(env) {
  return env.envVars.map(env => ({
    name: env.name,
    value: env.normalizedVal
  }));
}

function buildCommand(curDir, env, args) {

  // first group is a shared (built-in) env
  env = env.slice();
  let builtIns = env.shift();

  let envMap = env.reduce((envMap, pkg) => {
    envMap.set(pkg.packageJson.name, pkg);
    return envMap;
  }, new Map());

  let rules = [];

  let prelude = [
    {
      type: 'define',
      name: 'ESY__SANDBOX',
      value: '$(PWD)',
      assignment: '?=',
    },
  ];

  env.forEach(pkg => {
    let info = pkg.packageJson;
    let dependencies = collectTransitiveDependencies(envMap, info);

    let findlibPath = dependencies
      .map(dep => installDir(dep, 'lib'))
      .join(':');

    prelude.push({
      type: 'define',
      multiline: true,
      name: `${info.name}__FINDLIB_CONF`,
      value: `
path = "$(shell ocamlfind printconf path):${findlibPath}"
destdir = "${installDir(info.name, 'lib')}"
      `.trim(),
    });

    rules.push({
      type: 'rule',
      name: null,
      target: `${info.name}__findlib.conf`,
      dependencies: [buildDir(info.name, 'findlib.conf')],
      env: {},
      command: null,
    });

    rules.push({
      type: 'rule',
      name: null,
      target: buildDir(info.name, 'findlib.conf'),
      dependencies: [],
      env: {},
      export: ['ESY__SANDBOX', `${info.name}__FINDLIB_CONF`],
      command: `
mkdir -p $(@D)
echo "$${info.name}__FINDLIB_CONF" > $(@);
      `.trim(),
    });

    if (info.pjc && info.pjc.build) {
      let dependencies = [
        `${info.name}__findlib.conf`
      ];
      if (info.dependencies) {
        dependencies = dependencies.concat(Object.keys(info.dependencies));
      }
      rules.push({
        type: 'rule',
        name: ` *** Build ${info.name} ***`,
        target: info.name,
        dependencies: dependencies,
        export: ['ESY__SANDBOX'],
        env: []
          .concat(envToEnvList(builtIns))
          .concat(getBuildEnv(envMap, pkg))
          .concat(envToEnvList(pkg)),
        command: info.pjc.build,
      });
    } else {
      // TODO: Returning an empty rule. Is that really what we want here?
      rules.push({
        type: 'rule',
        name: ` *** Build ${info.name} ***`,
        target: info.name,
        export: ['ESY__SANDBOX'],
        dependencies: info.dependencies != null
          ? Object.keys(info.dependencies)
          : [],
        command: null,
      });
    }
  });

  console.log(renderMake(prelude.concat(rules)));
}

function getPkgEnv(envMap, pkg, current = false) {
  let prefix = current ? 'cur' : (pkg.packageJson.name + '_');
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

function getBuildEnv(envMap, pkg) {
  let info = pkg.packageJson;
  let name = info.name;
  let dependencies = info.dependencies != null
    ? Object.keys(info.dependencies)
    : [];
  let pkgEnv = [];

  pkgEnv = pkgEnv.concat([
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
    {
      name: 'OCAMLFIND_CONF',
      value: `$_build_tree/node_modules/${name}/findlib.conf`,
    },
  ]);

  pkgEnv = pkgEnv.concat(getPkgEnv(envMap, pkg, true));
  pkgEnv = pkgEnv.concat(getPkgEnv(envMap, pkg, false));

  if (dependencies.length > 0) {
    pkgEnv = pkgEnv.concat(
      ...dependencies.map(dep => getPkgEnv(envMap, envMap.get(dep), false))
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

function renderMake(items) {
  return items
    .map(item => {
      if (item.type === 'rule') {
        return renderMakeRule(item);
      } else if (item.type === 'define') {
        return renderMakeDefine(item);
      } else {
        throw new Error('Unknown make item:' + JSON.stringify(item));
      }
    })
    .join('\n\n');
}

function renderMakeDefine({name, value, multiline, assignment = '='}) {
  if (multiline) {
    return `
define ${name}
${value}
endef
    `.trim();
  } else {
    return `${name} ${assignment} ${value}`;
  }
}

function renderMakeRule(rule) {
  let header = `${rule.target}: ${rule.dependencies.join(' ')}`;

  let prelude = '';
  if (rule.export) {
    rule.export.forEach(name => {
      prelude = prelude + `export ${name}\n`;
    });
  }

  if (rule.command != null) {
    let recipe = escapeEnvVar(renderMakeRuleCommand(rule));
    if (rule.name != null) {
      return `${prelude}${header}\n\t@echo '${rule.name}'\n${recipe}`;
    } else {
      return `${prelude}${header}\n${recipe}`;
    }
  } else {
    return prelude + header;
  }
}

function renderMakeRuleCommand({env, command}) {
  command = command.split('\n').map(line => `\t${line}`).join('\n');
  if (env.length > 0) {
    let renderedEnv = env
      .filter(env => env.value != null)
      .map(env => `\texport ${env.name}=${env.value}; \\`)
      .join('\n');
    return `${renderedEnv}\n${command}`;
  } else {
    return command;
  }
}

function escapeEnvVar(command) {
  return command.replace(/\$([^\(])/g, '$$$$$1');
}

module.exports = buildCommand;
