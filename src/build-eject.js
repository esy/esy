/**
 * @flow
 */

import type {
  BuildSpec,
  BuildTask,
  BuildPlatform,
  BuildTaskCommand,
  Sandbox,
  Reporter,
} from './types';

import {sync as mkdirp} from 'mkdirp';
import createLogger from 'debug';
import outdent from 'outdent';

import * as Graph from './graph';
import * as S from './sandbox';
import * as T from './build-task.js';
import * as Config from './config.js';
import * as Env from './environment';
import * as Makefile from './Makefile';
import * as fs from './lib/fs';
import * as json from './lib/json.js';
import * as path from './lib/path';
import * as bashgen from './builders/bashgen';
import * as constants from './constants';

const log = createLogger('esy:makefile-builder');
const CWD = process.cwd();

const bin = {
  getStorePath: ejectedRootPath('bin', 'esyGetStorePath'),
  fastreplacestring: ejectedRootPath('bin', 'fastreplacestring.exe'),
  fastreplacestringSource: ejectedRootPath('bin', 'fastreplacestring.cpp'),
  ocamlrun: ejectedRootPath('bin', 'ocamlrun'),
};

const files = {
  getStorePath: {
    filename: ['bin/esyGetStorePath'],
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

  realpathSh: {
    filename: ['bin', 'realpath.sh'],
    contents: fs.readFileSync(require.resolve('../bin/realpath.sh')),
  },

  esyRuntimeSh: {
    filename: ['bin', 'esyRuntime.sh'],
    contents: fs.readFileSync(require.resolve('../bin/esyRuntime.sh')),
  },

  esyConfigSh: {
    filename: ['bin', 'esyConfig.sh'],
    contents: fs.readFileSync(require.resolve('../bin/esyConfig.sh')),
  },

  esyImportBuild: {
    filename: ['bin', 'esyImportBuild'],
    contents: fs.readFileSync(require.resolve('../bin/esyImportBuild')),
    executable: true,
  },

  esyExportBuild: {
    filename: ['bin', 'esyExportBuild'],
    contents: fs.readFileSync(require.resolve('../bin/esyExportBuild')),
    executable: true,
  },

  esyBuild: {
    filename: ['bin', 'esyBuild'],
    contents: outdent`
      #!/bin/bash

      build="$1"

      log=$(ocamlrun $ESY_EJECT__ROOT/bin/esyb build --build "$build")

      if [ $? -ne 0 ]; then
        echo "$log"
        exit 1
      fi

    `,
    executable: true,
  },
};

const preludeRuleSet = [
  // ESY_EJECT__ROOT is the root directory of the ejected Esy build
  // environment.
  Makefile.createRaw(
    outdent`
    export ESY_EJECT__ROOT := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
    export ESY_EJECT__PREFIX ?= $(HOME)/.esy
    export ESY_EJECT__STORE = $(shell ${bin.getStorePath} $(ESY_EJECT__PREFIX))
    export ESY_EJECT__SANDBOX ?= $(CURDIR)
    export ESY__PREFIX = $(ESY_EJECT__PREFIX)
    export ESY__SANDBOX = $(ESY_EJECT__SANDBOX)
    export ESY__SANDBOX = $(ESY_EJECT__SANDBOX)
    export PATH := $(ESY_EJECT__ROOT)/bin:$(PATH)
    ESYB = ocamlrun $(ESY_EJECT__ROOT)/bin/esyb
    `,
  ),
];

const compileFastreplacestringRule = Makefile.createRule({
  target: bin.fastreplacestring,
  dependencies: [bin.fastreplacestringSource],
  command: '@g++ -Ofast -o $(@) $(<) 2> /dev/null',
});

const compileOCamlRunRule = Makefile.createRule({
  target: bin.ocamlrun,
  command: outdent`
    @echo "Building OCaml bytecode runtime..."
    (cd ${ejectedRootPath('ocamlrun')} && tar xzf ocaml.tar.gz && bash postinstall.sh)
    ln -s ${ejectedRootPath('ocamlrun', 'install', 'bin', 'ocamlrun')} ${bin.ocamlrun}
  `,
});

const bootstrapOCamlRunRule = Makefile.createRule({
  target: 'bootstrap.ocamlrun',
  phony: true,
  dependencies: [compileOCamlRunRule],
});

const bootstrapToolsRule = Makefile.createRule({
  target: 'bootstrap.tools',
  phony: true,
  dependencies: [compileFastreplacestringRule],
});

const bootstrapRule = Makefile.createRule({
  target: 'bootstrap',
  phony: true,
  dependencies: [bootstrapOCamlRunRule, bootstrapToolsRule],
});

/**
 * Render `build` as Makefile (+ related files) into the supplied `outputPath`.
 */
export function eject(
  sandbox: Sandbox,
  outputPath: string,
  options: {
    buildPlatform: BuildPlatform,
    reporter: Reporter,
  },
) {
  const exportConfig = Config.create({
    reporter: options.reporter,
    storePath: '%store%',
    sandboxPath: '%sandbox%',
    buildPlatform: options.buildPlatform,
  });
  const rootTask = T.fromSandbox(sandbox, exportConfig);

  const makefileConfig = Config.create({
    reporter: options.reporter,
    storePath: '$ESY_EJECT__STORE',
    sandboxPath: '$ESY_EJECT__SANDBOX',
    buildPlatform: options.buildPlatform,
  });

  const buildFiles = [];

  for (const key in files) {
    buildFiles.push(files[key]);
  }

  function createBuildRule(
    build: BuildSpec,
    rule: {
      target: string,
      command: string,
      dependencies: Array<Makefile.MakefileItemDependency>,
    },
  ): Makefile.MakefileItem {
    const target = `${rule.target}.${build.packagePath === ''
      ? 'sandbox'
      : `sandbox/${build.packagePath}`}`;

    return Makefile.createRule({
      target,
      dependencies: [bootstrapRule, ...rule.dependencies],
      phony: true,
      command: rule.command,
    });
  }

  const tasks = [];

  function createBuildRules(directDependencies, allDependencies, task: BuildTask) {
    log(`visit ${task.spec.id}`);

    tasks.push(task);

    const exportTask = T.exportBuildTask(exportConfig, task);
    buildFiles.push({
      filename: ['build', `${task.spec.id}.json`],
      contents: json.stableStringifyPretty(exportTask),
    });

    const buildDependenciesRule = [];

    for (const depRules of directDependencies.values()) {
      buildDependenciesRule.push(depRules.buildRule);
    }

    const rules = [];
    for (const depRules of allDependencies.values()) {
      rules.push(depRules.buildShellRule);
    }

    const buildRule = createBuildRule(task.spec, {
      target: 'build',
      command: outdent`
        @echo 'Building package: ${task.spec.name}'
        esyBuild $(ESY_EJECT__ROOT)/build/${task.spec.id}.json
      `,
      dependencies: buildDependenciesRule,
    });

    const buildShellRule = createBuildRule(task.spec, {
      target: 'shell',
      command: outdent`
        @$(ESYB) shell --build $(ESY_EJECT__ROOT)/build/${task.spec.id}.json
        `,
      dependencies: buildDependenciesRule,
    });

    return {
      buildRule,
      buildShellRule,
      rules: Makefile.createGroup(...rules),
    };
  }

  log(`eject build environment into <ejectRootDir>=./${path.relative(CWD, outputPath)}`);

  const {
    buildRule: rootBuildRule,
    buildShellRule: rootBuildShellRule,
    rules,
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
    dependencies: [],
    command: outdent`
      rm -f ${compileFastreplacestringRule.target}
      rm -f ${bin.ocamlrun}
      rm -rf ${ejectedRootPath('ocamlrun')}
    `,
  });

  const listInstallPathsRule = Makefile.createRule({
    target: 'list-install-paths',
    phony: true,
    command:
      '@' +
      tasks
        .map(task => `echo "${makefileConfig.getFinalInstallPath(task.spec)}"`)
        .join('\n'),
  });

  const makefileFile = {
    filename: ['Makefile'],
    contents: Makefile.renderMakefile([
      ...preludeRuleSet,
      buildRule,
      buildShellRule,
      cleanRule,
      listInstallPathsRule,
      rules,
    ]),
  };

  const sandboxEnvFile = {
    filename: ['sandbox-env'],
    contents: outdent`
      ${bashgen.defineEsyUtil}

      # Set the default value for ESY_EJECT__PREFIX if it's not defined.
      if [ -z \${ESY_EJECT__PREFIX+x} ]; then
        export ESY_EJECT__PREFIX="$HOME/.esy"
      fi

      # Set the default value for ESY_EJECT__STORE if it's not defined.
      if [ -z \${ESY_EJECT__STORE+x} ]; then
        export ESY_EJECT__STORE=$(esyGetStorePathFromPrefix "$ESY_EJECT__PREFIX")
      fi

      ${Env.printEnvironment(S.getSandboxEnv(sandbox, makefileConfig))}
    `,
  };

  log('build environment');
  return Promise.all(
    buildFiles
      .map(file => emitFile(outputPath, file))
      .concat([
        emitFile(outputPath, sandboxEnvFile),
        emitFile(outputPath, makefileFile),
        emitOcamlrun(outputPath),
        emitEsyb(outputPath),
      ]),
  );
}

async function emitOcamlrun(outputPath: string) {
  const ocamlrunPath = path.join(outputPath, 'ocamlrun');
  await fs.mkdirp(ocamlrunPath);
  await fs.copy(
    require.resolve('@esy-ocaml/ocamlrun/ocaml.tar.gz'),
    path.join(ocamlrunPath, 'ocaml.tar.gz'),
  );
  await fs.copy(
    require.resolve('@esy-ocaml/ocamlrun/postinstall.sh'),
    path.join(ocamlrunPath, 'postinstall.sh'),
  );
  await fs.copy(
    require.resolve('@esy-ocaml/ocamlrun/test'),
    path.join(ocamlrunPath, 'test'),
  );
}

async function emitEsyb(outputPath: string) {
  await fs.copy(
    require.resolve('@esy-ocaml/esyb/esyb.bc'),
    path.join(outputPath, 'bin', 'esyb'),
  );
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
