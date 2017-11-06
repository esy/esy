/**
 * @flow
 */

import type {
  BuildSpec,
  BuildTask,
  BuildTaskCommand,
  Config,
  BuildSandbox,
} from '../types';

import {sync as mkdirp} from 'mkdirp';
import createLogger from 'debug';
import outdent from 'outdent';

import * as Graph from '../graph';
import * as Task from '../build-task';
import * as Sandbox from '../sandbox';
import * as Env from '../environment';
import * as Makefile from '../Makefile';
import {normalizePackageName} from '../util';
import {renderEnv, renderSandboxSbConfig} from './util';
import {singleQuote} from '../lib/shell';
import * as fs from '../lib/fs';
import * as path from '../lib/path';
import * as bashgen from './bashgen';
import * as constants from '../constants';

const log = createLogger('esy:makefile-builder');
const CWD = process.cwd();

function createRenderEnvRule(params: {target: string, input: string}) {
  return Makefile.createRule({
    target: params.target,
    dependencies: [params.input, initRootRule.target],
    shell: '/bin/bash',
    command: `@$(env_init) ${bin.renderEnv} $(<) $(@)`,
  });
}

function createMkdirRule(params: {target: string}) {
  return Makefile.createRule({
    target: params.target,
    command: `@mkdir -p $(@)`,
  });
}

const bin = {
  renderEnv: ejectedRootPath('bin', 'render-env'),
  getStorePath: ejectedRootPath('bin', 'get-store-path'),
  realpath: ejectedRootPath('bin', 'realpath'),
  realpathSource: ejectedRootPath('bin', 'realpath.c'),
  fastreplacestring: ejectedRootPath('bin', 'fastreplacestring.exe'),
  fastreplacestringSource: ejectedRootPath('bin', 'fastreplacestring.cpp'),
  runtime: ejectedRootPath('bin', 'runtime.sh'),
};

const files = {
  commandEnv: {
    filename: ['bin/render-env'],
    executable: true,
    contents: outdent`
      #!/bin/bash

      set -e
      set -o pipefail

      _TMPDIR_GLOBAL=$($ESY_EJECT__ROOT/bin/realpath "/tmp")

      if [ -d "$TMPDIR" ]; then
        _TMPDIR=$($ESY_EJECT__ROOT/bin/realpath "$TMPDIR")
      else
        _TMPDIR="/does/not/exist"
      fi

      sed \\
        -e "s|\\$ESY_EJECT__STORE|$ESY_EJECT__STORE|g"          \\
        -e "s|\\$ESY_EJECT__SANDBOX|$ESY_EJECT__SANDBOX|g"      \\
        -e "s|\\$ESY_EJECT__ROOT|$ESY_EJECT__ROOT|g"      \\
        -e "s|\\$TMPDIR_GLOBAL|$_TMPDIR_GLOBAL|g"   \\
        -e "s|\\$TMPDIR|$_TMPDIR|g"                 \\
        $1 > $2
    `,
  },

  getStorePath: {
    filename: ['bin/get-store-path'],
    executable: true,
    contents: outdent`
      #!/bin/bash

      set -e
      set -o pipefail

      ${bashgen.defineEsyUtil}

      esyGetStorePathFromPrefix "$1"
    `,
  },

  fastreplacestringSource: {
    filename: ['bin', 'fastreplacestring.cpp'],
    contents: fs.readFileSync(require.resolve('fastreplacestring/fastreplacestring.cpp')),
  },

  realpathSource: {
    filename: ['bin', 'realpath.c'],
    contents: outdent`
      #include<stdlib.h>

      main(int cc, char**vargs) {
        puts(realpath(vargs[1], 0));
        exit(0);
      }
    `,
  },

  runtimeSource: {
    filename: ['bin', 'runtime.sh'],
    contents: fs.readFileSync(require.resolve('./shell-builder.sh')),
  },
};

const preludeRuleSet = [
  Makefile.createRaw('SHELL := env -i /bin/bash --norc --noprofile'),

  // ESY_EJECT__ROOT is the root directory of the ejected Esy build
  // environment.
  Makefile.createRaw(
    'ESY_EJECT__ROOT := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))',
  ),

  // ESY_EJECT__PREFIX is the directory where esy keeps the store and other
  // artefacts
  Makefile.createRaw('ESY_EJECT__PREFIX ?= $(HOME)/.esy'),

  Makefile.createRaw(
    `ESY_EJECT__STORE = $(shell ${bin.getStorePath} $(ESY_EJECT__PREFIX))`,
  ),

  // ESY_EJECT__SANDBOX is the sandbox directory, the directory where the root
  // package resides.
  Makefile.createRaw('ESY_EJECT__SANDBOX ?= $(CURDIR)'),
];

const compileRealpathRule = Makefile.createRule({
  target: bin.realpath,
  dependencies: [bin.realpathSource],
  shell: '/bin/bash',
  command: '@gcc -o $(@) -x c $(<) 2> /dev/null',
});

const compileFastreplacestringRule = Makefile.createRule({
  target: bin.fastreplacestring,
  dependencies: [bin.fastreplacestringSource],
  shell: '/bin/bash',
  command: '@g++ -Ofast -o $(@) $(<) 2> /dev/null',
});

const initStoreRule = Makefile.createRule({
  target: 'esy-store',
  phony: true,
  dependencies: [
    createMkdirRule({target: storePath(constants.STORE_BUILD_TREE)}),
    createMkdirRule({target: storePath(constants.STORE_INSTALL_TREE)}),
    createMkdirRule({target: storePath(constants.STORE_STAGE_TREE)}),
    createMkdirRule({target: localStorePath(constants.STORE_BUILD_TREE)}),
    createMkdirRule({target: localStorePath(constants.STORE_INSTALL_TREE)}),
    createMkdirRule({target: localStorePath(constants.STORE_STAGE_TREE)}),
  ],
});

const initRootRule = Makefile.createRule({
  target: 'esy-root',
  phony: true,
  dependencies: [compileRealpathRule, compileFastreplacestringRule],
});

const defineSandboxEnvRule = Makefile.createDefine({
  name: `env_init`,
  value: [
    {
      CI: process.env.CI ? process.env.CI : null,
      TMPDIR: '$(TMPDIR)',
      ESY_EJECT__PREFIX: '$(ESY_EJECT__PREFIX)',
      ESY_EJECT__STORE: storePath(),
      ESY_EJECT__SANDBOX: sandboxPath(),
      ESY_EJECT__ROOT: ejectedRootPath(),
    },
  ],
});

/**
 * Render `build` as Makefile (+ related files) into the supplied `outputPath`.
 */
export function eject(
  sandbox: BuildSandbox,
  outputPath: string,
  config: Config<path.Path>,
) {
  const buildFiles = [];

  function generateMetaRule({filename}) {
    const input = ejectedRootPath('records', `${filename}.in`);
    const target = ejectedRootPath('records', filename);
    const rule = createRenderEnvRule({target, input});
    return rule;
  }

  function createBuildRule(
    build: BuildSpec,
    rule: {
      target: string,
      command: string,
      withBuildEnv?: boolean,
      dependencies: Array<Makefile.MakefileItemDependency>,
    },
  ): Makefile.MakefileItem {
    const packageName = normalizePackageName(build.id);
    const command = [];
    if (rule.withBuildEnv) {
      command.push(outdent`
        @$(env_init) $(env__${packageName}) source ${bin.runtime}
        cd $esy_build__source_root
      `);
    }
    command.push(rule.command);

    const target = `${rule.target}.${build.sourcePath === ''
      ? 'sandbox'
      : `sandbox/${build.sourcePath}`}`;

    return Makefile.createRule({
      target,
      dependencies: [bootstrapRule, ...rule.dependencies],
      phony: true,
      command,
    });
  }

  function createBuildRules(directDependencies, allDependencies, task: BuildTask) {
    log(`visit ${task.spec.id}`);

    const packageName = normalizePackageName(task.spec.id);
    const packagePath = task.spec.sourcePath.split(path.sep).filter(Boolean);

    const finalInstallPath = config.getFinalInstallPath(task.spec);

    // Emit env
    buildFiles.push({
      filename: packagePath.concat('eject-env'),
      contents: renderEnv(task.env),
    });

    // Generate macOS sandbox configuration (sandbox-exec command)
    buildFiles.push({
      filename: packagePath.concat('sandbox.sb.in'),
      contents: renderSandboxSbConfig(task.spec, config, {
        allowFileWrite: ['$TMPDIR', '$TMPDIR_GLOBAL'],
      }),
    });

    const envRule = Makefile.createDefine({
      name: `env__${packageName}`,
      value: [
        `source ${ejectedRootPath(...packagePath, 'eject-env')}`,
        {
          esy_build__sandbox_config_darwin: ejectedRootPath(...packagePath, 'sandbox.sb'),
          esy_build__source_root: path.join(config.sandboxPath, task.spec.sourcePath),
          esy_build__install_root: finalInstallPath,
          esy_build__build_type: task.spec.buildType,
          esy_build__source_type: task.spec.sourceType,
          esy_build__build_command: renderBuildTaskCommand(task.buildCommand),
          esy_build__install_command: renderBuildTaskCommand(task.installCommand),
        },
      ],
    });

    const buildDependenciesRule = [];
    const cleanDependenciesRule = [];

    for (const depRules of directDependencies.values()) {
      buildDependenciesRule.push(depRules.buildRule);
      cleanDependenciesRule.push(depRules.cleanRule);
    }

    const rules = [];
    for (const depRules of allDependencies.values()) {
      rules.push(depRules.buildShellRule);
    }

    const sandboxConfigRule = createRenderEnvRule({
      target: ejectedRootPath(...packagePath, 'sandbox.sb'),
      input: ejectedRootPath(...packagePath, 'sandbox.sb.in'),
    });

    const buildRule = createBuildRule(task.spec, {
      target: 'build',
      command: 'esyBuild',
      withBuildEnv: true,
      dependencies: [envRule, sandboxConfigRule, ...buildDependenciesRule],
    });

    const buildShellRule = createBuildRule(task.spec, {
      target: 'shell',
      command: 'esyShell',
      withBuildEnv: true,
      dependencies: [envRule, sandboxConfigRule, ...buildDependenciesRule],
    });

    const cleanRule = createBuildRule(task.spec, {
      target: 'clean',
      command: outdent`
        @rm -f ${sandboxConfigRule.target}
      `,
      dependencies: [...cleanDependenciesRule],
    });

    const dependenciesInstallPathList = Array.from(allDependencies.values()).map(d =>
      config.getFinalInstallPath(d.task.spec),
    );

    return {
      task: task,
      buildRule,
      buildShellRule,
      cleanRule,
      rules: Makefile.createGroup(...rules),
      finalInstallPathSet: dependenciesInstallPathList.concat(finalInstallPath),
    };
  }

  log(`eject build environment into <ejectRootDir>=./${path.relative(CWD, outputPath)}`);

  // Emit build artefacts for packages
  log('process dependency graph');
  const rootTask = Task.fromBuildSandbox(sandbox, config);

  const finalInstallPathSetMetaRule = generateMetaRule({
    filename: 'final-install-path-set.txt',
  });

  const storePathMetaRule = generateMetaRule({
    filename: 'store-path.txt',
  });

  const bootstrapRule = Makefile.createRule({
    target: 'bootstrap',
    phony: true,
    dependencies: [
      finalInstallPathSetMetaRule,
      storePathMetaRule,
      defineSandboxEnvRule,
      initRootRule,
      initStoreRule,
    ],
  });

  const {
    buildRule: rootBuildRule,
    buildShellRule: rootBuildShellRule,
    cleanRule: rootCleanRule,
    rules,
    finalInstallPathSet,
  } = Graph.topologicalFold(rootTask, createBuildRules);

  const buildRule = Makefile.createRule({
    target: 'build',
    phony: true,
    dependencies: [rootBuildRule],
  });

  const buildShellRule = Makefile.createRule({
    target: 'build-shell',
    phony: true,
    dependencies: [rootBuildShellRule],
  });

  // TODO: this can be generated automatically from non-phony rules
  const cleanRule = Makefile.createRule({
    target: 'clean',
    phony: true,
    dependencies: [rootCleanRule],
    command: outdent`
      @rm -f ${sandboxPath(constants.BUILD_TREE_SYMLINK)}
      rm -f ${sandboxPath(constants.INSTALL_TREE_SYMLINK)}
      rm -f ${compileRealpathRule.target}
      rm -f ${compileFastreplacestringRule.target}
      rm -f ${storePathMetaRule.target}
      rm -f ${finalInstallPathSetMetaRule.target}
    `,
  });

  const makefileFile = {
    filename: ['Makefile'],
    contents: Makefile.renderMakefile([
      ...preludeRuleSet,
      buildRule,
      buildShellRule,
      cleanRule,
      rules,
    ]),
  };

  const sandboxEnvFile = {
    filename: ['sandbox-env'],
    contents: outdent`
      ${bashgen.defineEsyUtil}

      # Set the default value for ESY_EJECT__STORE if it's not defined.
      if [ -z \${ESY_EJECT__STORE+x} ]; then
        export ESY_EJECT__STORE=$(esyGetStorePathFromPrefix "$HOME/.esy")
      fi

      ${Env.printEnvironment(Sandbox.getSandboxEnv(rootTask, config))}
    `,
  };

  log('build environment');
  Promise.all([
    ...buildFiles.map(file => emitFile(outputPath, file)),
    emitFile(outputPath, {
      filename: ['records', `final-install-path-set.txt.in`],
      contents: finalInstallPathSet.join('\n'),
    }),
    emitFile(outputPath, {
      filename: ['records', `store-path.txt.in`],
      contents: '$ESY_EJECT__STORE',
    }),
    emitFile(outputPath, files.commandEnv),
    emitFile(outputPath, files.getStorePath),
    emitFile(outputPath, files.fastreplacestringSource),
    emitFile(outputPath, files.realpathSource),
    emitFile(outputPath, files.runtimeSource),
    emitFile(outputPath, sandboxEnvFile),
    emitFile(outputPath, makefileFile),
  ]);
}

async function emitFile(
  outputPath: string,
  file: {filename: Array<string>, contents: string, executable?: boolean},
) {
  const filename = path.join(outputPath, ...file.filename);
  log(`emit <ejectRootDir>/${file.filename.join('/')}`);
  await fs.mkdirp(path.dirname(filename));
  await fs.writeFile(filename, file.contents);
  if (file.executable) {
    // fs.constants only became supported in node 6.7 or so.
    const mode = fs.constants && fs.constants.S_IRWXU ? fs.constants.S_IRWXU : 448;
    await fs.chmod(filename, mode);
  }
}

export function renderBuildTaskCommand(command: Array<BuildTaskCommand>) {
  return command.map(c => Makefile.quoted(singleQuote(c.renderedCommand)));
}

function ejectedRootPath(...segments) {
  return path.join('$(ESY_EJECT__ROOT)', ...segments);
}

function sandboxPath(...segments) {
  return path.join('$(ESY_EJECT__SANDBOX)', ...segments);
}

function storePath(...segments) {
  return path.join('$(ESY_EJECT__STORE)', ...segments);
}

function localStorePath(...segments) {
  return sandboxPath('node_modules', '.cache', '_esy', 'store', ...segments);
}
