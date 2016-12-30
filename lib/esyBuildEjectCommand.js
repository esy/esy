/**
 * @flow
 */

import type {MakeItem, MakeRawItem, MakeDefine, MakeRule} from './Makefile';
import type {
  Sandbox,
  PackageInfo
} from './Sandbox';
import type {EnvironmentGroup} from './PackageEnvironment';

const childProcess = require('child_process');
const fs = require('fs');
const crypto  = require('crypto');
const path = require('path');
const outdent = require('outdent');
const {flattenArray} = require('./Utility');

const RUNTIME = fs.readFileSync(require.resolve('./esyBuildRuntime.sh'), 'utf8');

const {
  traversePackageDependencyTree,
  collectTransitiveDependencies,
  packageInfoKey,
} = require('./Sandbox');
const PackageEnvironment = require('./PackageEnvironment');
const Makefile = require('./Makefile');

function buildEjectCommand(
  sandbox: Sandbox,
  args: Array<string>,
  options: {buildInStore?: boolean} = {buildInStore: true}
) {

  let sandboxPackageName = sandbox.packageInfo.packageJson.name;

  let sandboxPath = (packageInfo, tree: '_install' | '_build', ...path) => {
    let packageName = packageInfo.packageJson.name;
    let packageKey = packageInfoKey(sandbox.env, packageInfo);
    let isRootPackage = packageName === sandbox.packageInfo.packageJson.name;
    if (isRootPackage) {
      return ['$(ESY__SANDBOX)', tree, ...path].join('/');
    }
    return options.buildInStore
      ? ['$(ESY__STORE)', tree, packageKey, ...path].join('/')
      : ['$(ESY__SANDBOX)', tree, 'node_modules', packageName, ...path].join('/');
  };

  let buildPath = (packageInfo, ...path) =>
    sandboxPath(packageInfo, '_build', ...path);

  let installPath = (packageInfo, ...path) =>
    sandboxPath(packageInfo, '_install', ...path);

  let prelude: Array<MakeDefine | MakeRawItem> = [
    {
      type: 'raw',
      value: `SHELL = ${sandbox.env.SHELL}`,
    },
    {
      type: 'raw',
      value: 'ESY__STORE ?= $(HOME)/.esy/store',
    },
    {
      type: 'raw',
      value: `ESY__RUNTIME ?= $(HOME)/.esy/runtime-${hash(RUNTIME)}.sh`,
    },
    {
      type: 'raw',
      value: 'ESY__SANDBOX ?= $(CURDIR)',
    },
  ];

  let rules: Array<MakeItem> = [

    {
      type: 'rule',
      target: 'build',
      phony: true,
      dependencies: [`${sandboxPackageName}.build`],
    },
    {
      type: 'rule',
      target: 'rebuild',
      phony: true,
      dependencies: [`${sandboxPackageName}.rebuild`],
    },
    {
      type: 'rule',
      target: 'shell',
      phony: true,
      dependencies: [`${sandboxPackageName}.shell`],
    },
    {
      type: 'rule',
      target: 'clean',
      phony: true,
      command: 'rm -rf $(ESY__SANDBOX)/_build $(ESY__SANDBOX)/_install',
    },
    {
      type: 'rule',
      target: '$(ESY__STORE)/_install $(ESY__STORE)/_build',
      command: 'mkdir -p $(@)',
    },
    {
      type: 'rule',
      target: 'esy-store',
      phony: true,
      dependencies: ['$(ESY__STORE)/_install',  '$(ESY__STORE)/_build'],
    },
    {
      type: 'rule',
      target: 'esy-runtime',
      phony: true,
      dependencies: ['$(ESY__RUNTIME)'],
    },
    {
      type: 'file',
      name: '$(ESY__RUNTIME)',
      value: RUNTIME
    },
  ];

  traversePackageDependencyTree(
    sandbox.packageInfo,
    (packageInfo) => {
      let {normalizedName, packageJson} = packageInfo;
      let buildHash = packageInfoKey(sandbox.env, packageInfo);

      /**
       * Produce a package-scoped Makefile rule which executes its command in
       * the package's environment and working directory.
       */
      function definePackageRule(rule: {
        target: string;
        dependencies?: Array<string>;
        command?: ?string;
      }) {
        let {
          target,
          command,
          dependencies = []
        } = rule;
        rules.push({
          type: 'rule',
          target: packageTarget(target),
          dependencies: ['esy-store', 'esy-runtime', ...dependencies],
          phony: true,
          command: command != null
            ? outdent`
              export ESY__STORE=$(ESY__STORE); \\
              export ESY__SANDBOX=$(ESY__SANDBOX); \\
              export ESY__RUNTIME=$(ESY__RUNTIME); \\
              export esy_build__source="${packageInfo.source}"; \\
              export esy_build__source_type="${packageInfo.sourceType}"; \\
              $(${packageEnv}) \\
              cd $cur__root; \\
              source $(ESY__RUNTIME); \\
              ${command}
            `
            : null
        });
      }

      function packageTarget(target, packageName = packageJson.name) {
        return `${packageName}.${target}`;
      }

      let isRootPackage = packageJson.name === sandboxPackageName;

      let buildEnvironment = PackageEnvironment.calculateEnvironment(
        sandbox,
        packageInfo,
        {buildInStore: options.buildInStore}
      );

      let dependencies = Object
        .keys(packageInfo.dependencyTree)
        .map(dep => packageTarget('build', dep));
      let allDependencies = collectTransitiveDependencies(packageInfo);
      let findlibConf = buildPath(packageInfo, '_esy_findlib.conf');
      let packageEnv = `${packageJson.name}__env`;

      rules.push({
        type: 'file',
        name: findlibConf,
        value: outdent`
          path = "${allDependencies.map(dep => installPath(dep, 'lib')).join(':')}"
          destdir = "${installPath(packageInfo, 'lib')}"
          ldconf = "ignore"
          ocamlc = "ocamlc.opt"
          ocamldep = "ocamldep.opt"
          ocamldoc = "ocamldoc.opt"
          ocamllex = "ocamllex.opt"
          ocamlopt = "ocamlopt.opt"
        `
      });

      rules.push({
        type: 'define',
        name: packageEnv,
        value: renderEnv(buildEnvironment),
      });

      definePackageRule({
        target: 'findlib.conf',
        dependencies: [findlibConf],
      });

      definePackageRule({
        target: 'clean',
        command: 'esy-clean'
      });

      definePackageRule({
        target: 'shell',
        dependencies: [packageTarget('findlib.conf'), ...dependencies],
        command: 'esy-shell'
      });

      definePackageRule({
        target: 'build',
        dependencies: [packageTarget('findlib.conf'), ...dependencies],
        command: packageInfo.sourceType === 'local' ? 'esy-force-build' : 'esy-build'
      });
    });

  let allRules = [].concat(prelude).concat(rules);
  console.log(Makefile.renderMakefile(allRules));
}

function hash(value: string): string {
  return crypto.createHash('sha1').update(value).digest('hex');
}

function renderEnv(groups: Array<EnvironmentGroup>): string {
  let env = flattenArray(groups.map(group => group.envVars));
  return env
    .filter(env => env.value != null)
    // $FlowFixMe: make sure env.value is refined above
    .map(env => `export ${env.name}="${env.value}";`)
    .join('\\\n');
}

module.exports = buildEjectCommand;
