/**
 * @flow
 */

import type {PackageDb} from './PackageDb';
import type {MakeRawItem, MakeDefine, MakeRule} from './Makefile';

const childProcess = require('child_process');
const path = require('path');
const outdent = require('outdent');

const {
  traversePackageDb,
  collectTransitiveDependencies,
  collectDependencies,
} = require('./PackageDb');
const PackageEnvironment = require('./PackageEnvironment');
const Makefile = require('./Makefile');

const ESY_SANDBOX_REF = '$(ESY__SANDBOX)';

function buildCommand(packageDb: PackageDb, args: Array<string>) {

  function installDir(pkgName, ...args) {
    let isRootPackage = pkgName === packageDb.rootPackageName;
    return isRootPackage
      ? path.join('$(ESY__SANDBOX)', '_install', ...args)
      : path.join('$(ESY__SANDBOX)', '_install', 'node_modules', pkgName, ...args);
  }

  function buildDir(pkgName, ...args) {
    let isRootPackage = pkgName === packageDb.rootPackageName;
    return isRootPackage
      ? path.join('$(ESY__SANDBOX)', '_build', ...args)
      : path.join('$(ESY__SANDBOX)', '_build', 'node_modules', pkgName, ...args);
  }

  let rules: Array<MakeRule> = [
    {
      type: 'rule',
      name: '*** Build root package ***',
      target: 'build',
      dependencies: [`${packageDb.rootPackageName}.build`],
    },
    {
      type: 'rule',
      name: '*** Rebuild root package ***',
      target: 'rebuild',
      dependencies: [`${packageDb.rootPackageName}.rebuild`],
    },
    {
      type: 'rule',
      name: '*** Root package shell ***',
      target: 'shell',
      dependencies: [`${packageDb.rootPackageName}.shell`],
    },
    {
      type: 'rule',
      name: '*** Remove sandbox installations / build artifacts ***',
      target: 'clean',
      command: 'rm -rf $(ESY__SANDBOX)/_build $(ESY__SANDBOX)/_install',
    },
  ];

  let prelude: Array<MakeDefine | MakeRawItem> = [
    {
      type: 'raw',
      value: 'SHELL = /bin/bash',
    },
    {
      type: 'raw',
      value: 'ESY__SANDBOX ?= $(CURDIR)',
    },
    {
      type: 'define',
      name: 'ESY__PREPARE_CURRENT_INSTALL_TREE',
      value: outdent`
        mkdir -p \\
          $cur__install \\
          $cur__lib \\
          $cur__bin \\
          $cur__sbin \\
          $cur__man \\
          $cur__doc \\
          $cur__share \\
          $cur__etc;
      `,
    },
  ];

  traversePackageDb(
    packageDb,
    ({normalizedName, packageJsonFilePath, packageJson}) => {

      /**
       * Produce a package-scoped Makefile rule which executes its command in
       * the package's environment and working directory.
       */
      function makePackageRule(rule: {
        target: string;
        dependencies?: Array<string>;
        command?: ?string;
      }) {
        let {
          target,
          command,
          dependencies
        } = rule;
        return {
          type: 'rule',
          name: `*** ${packageJson.name}: ${target} ***`,
          target: `${packageJson.name}.${target}`,
          dependencies,
          exportEnv: ['SHELL', 'ESY__SANDBOX'],
          command: command != null
            ? outdent`
              $(${normalizedName}__ENV)\\
              cd $cur__root; \\
              ${command}
            `
            : null
        };
      }

      let isRootPackage = packageJson.name === packageDb.rootPackageName;
      let allDependencies = collectTransitiveDependencies(packageDb, packageJson.name);

      let buildEnvironment = PackageEnvironment.calculateEnvironment(
        packageDb,
        packageJson.name
      );

      // Produce macro with rendered findlib.conf content.
      let findlibPath = allDependencies
        .map(dep => installDir(dep, 'lib'))
        .join(':');

      prelude.push({
        type: 'define',
        name: `${normalizedName}__FINDLIB_CONF`,
        value: outdent`
          path = "${findlibPath}"
          destdir = "${installDir(packageJson.name, 'lib')}"
        `
      });

      // Produce macro with rendered package's environment.
      prelude.push({
        type: 'define',
        name: `${normalizedName}__ENV`,
        value: Makefile.renderEnv(buildEnvironment),
      });

      rules.push({
        type: 'rule',
        name: null,
        target: buildDir(packageJson.name, 'findlib.conf'),
        exportEnv: ['ESY__SANDBOX', `${normalizedName}__FINDLIB_CONF`],
        command: outdent`
          mkdir -p $(@D)
          echo "$${normalizedName}__FINDLIB_CONF" > $(@);
        `
      });

      rules.push(makePackageRule({
        target: 'findlib.conf',
        dependencies: [buildDir(packageJson.name, 'findlib.conf')],
      }));

      rules.push(makePackageRule({
        target: 'shell',
        command: outdent`
          $SHELL \\
            --noprofile \\
            --rcfile <(echo 'export PS1="[$cur__name sandbox] $ "')
          `,
      }));

      rules.push(makePackageRule({
        target: 'clean',
        command: 'rm -rf $cur__install $cur__target_dir'
      }));

      let dependencies = collectDependencies(packageDb, packageJson.name)
                         .map(dep => `${dep}.build`);

      if (packageJson.pjc && packageJson.pjc.build) {
        let buildCommand = packageJson.pjc.build;
        rules.push(makePackageRule({
          target: 'build',
          dependencies: [
            `${packageJson.name}.findlib.conf`,
            ...dependencies
          ],
          command: isRootPackage
          ? outdent`
            $(ESY__PREPARE_CURRENT_INSTALL_TREE)\\
            ${buildCommand}
          `
          : outdent`
            if [ ! -d "$cur__install" ]; then \\
              $(ESY__PREPARE_CURRENT_INSTALL_TREE)\\
              ${buildCommand}; \\
            fi
          `
        }));
        rules.push(makePackageRule({
          target: 'rebuild',
          dependencies: [
            `${packageJson.name}.findlib.conf`,
            ...dependencies
          ],
          command: outdent`
            $(ESY__PREPARE_CURRENT_INSTALL_TREE)\\
            ${buildCommand}
          `,
        }));
      } else {
        rules.push(makePackageRule({
          target: 'rebuild',
          dependencies,
        }));
        rules.push(makePackageRule({
          target: 'build',
          dependencies,
        }));
      }
    });

  let allRules = [].concat(prelude).concat(rules);
  console.log(Makefile.renderMakefile(allRules));
}

module.exports = buildCommand;
