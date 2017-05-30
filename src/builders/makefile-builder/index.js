/**
 * @flow
 */

import type {BuildSpec, BuildTask, BuildConfig, BuildSandbox} from '../../types';

import * as path from 'path';
import * as fs from 'fs';
import {sync as mkdirp} from 'mkdirp';
import createLogger from 'debug';
import outdent from 'outdent';

import * as Graph from '../../graph';
import * as Config from '../../build-config';
import * as Task from '../../build-task';
import * as Makefile from '../../Makefile';
import {normalizePackageName} from '../../util';
import {renderEnv, renderSandboxSbConfig} from '../util';

const log = createLogger('esy:makefile-builder');
const CWD = process.cwd();

const RUNTIME = fs.readFileSync(path.join(__dirname, 'runtime.sh'), 'utf8');

const STORE_PATH = '$ESY_EJECT__STORE';
const SANDBOX_PATH = '$ESY_EJECT__SANDBOX';

const fastReplaceStringSrc = fs.readFileSync(
  require.resolve('fastreplacestring/fastreplacestring.cpp'),
  'utf8',
);

/**
 * Note that Makefile based builds defers exact locations of sandbox and store
 * to some later point because ejected builds can be transfered to other
 * machines.
 *
 * That means that build env is generated in a way which can be configured later
 * with `$ESY_EJECT__SANDBOX` and `$ESY__STORE` environment variables.
 */
export const buildConfig: BuildConfig = Config.createConfig({
  storePath: STORE_PATH,
  sandboxPath: SANDBOX_PATH,
});

/**
 * Render `build` as Makefile (+ related files) into the supplied `outputPath`.
 */
export function renderToMakefile(sandbox: BuildSandbox, outputPath: string) {
  log(`eject build environment into <ejectRootDir>=./${path.relative(CWD, outputPath)}`);
  const ruleSet: Makefile.MakeItem[] = [
    {
      type: 'raw',
      value: 'SHELL := env -i /bin/bash --norc --noprofile',
    },

    // ESY_EJECT__ROOT is the root directory of the ejected Esy build
    // environment.
    {
      type: 'raw',
      value: 'ESY_EJECT__ROOT := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))',
    },

    // ESY_EJECT__STORE is the directory where build artifacts should be stored.
    {
      type: 'raw',
      value: `ESY_EJECT__STORE ?= $(HOME)/.esy/${Config.ESY_STORE_VERSION}`,
    },

    // ESY_EJECT__SANDBOX is the sandbox directory, the directory where the root
    // package resides.
    {
      type: 'raw',
      value: 'ESY_EJECT__SANDBOX ?= $(CURDIR)',
    },

    // These are public API

    {
      type: 'rule',
      target: 'build',
      phony: true,
      dependencies: [createBuildRuleName(sandbox.root, 'build')],
    },
    {
      type: 'rule',
      target: 'build-shell',
      phony: true,
      dependencies: [createBuildRuleName(sandbox.root, 'shell')],
    },
    {
      type: 'rule',
      target: 'clean',
      phony: true,
      command: outdent`
        rm $(ESY_EJECT__SANDBOX)/_build
        rm $(ESY_EJECT__SANDBOX)/_install
      `,
    },

    // Create store directory structure
    {
      type: 'rule',
      target: [
        `$(ESY_EJECT__STORE)/${Config.STORE_BUILD_TREE}`,
        `$(ESY_EJECT__STORE)/${Config.STORE_INSTALL_TREE}`,
        `$(ESY_EJECT__STORE)/${Config.STORE_STAGE_TREE}`,
        `$(ESY_EJECT__SANDBOX)/node_modules/.cache/_esy/store/${Config.STORE_BUILD_TREE}`,
        `$(ESY_EJECT__SANDBOX)/node_modules/.cache/_esy/store/${Config.STORE_INSTALL_TREE}`,
        `$(ESY_EJECT__SANDBOX)/node_modules/.cache/_esy/store/${Config.STORE_STAGE_TREE}`,
      ].join(' '),
      command: 'mkdir -p $(@)',
    },
    {
      type: 'rule',
      target: 'esy-store',
      phony: true,
      dependencies: [
        `$(ESY_EJECT__STORE)/${Config.STORE_BUILD_TREE}`,
        `$(ESY_EJECT__STORE)/${Config.STORE_INSTALL_TREE}`,
        `$(ESY_EJECT__STORE)/${Config.STORE_STAGE_TREE}`,
        `$(ESY_EJECT__SANDBOX)/node_modules/.cache/_esy/store/${Config.STORE_BUILD_TREE}`,
        `$(ESY_EJECT__SANDBOX)/node_modules/.cache/_esy/store/${Config.STORE_INSTALL_TREE}`,
        `$(ESY_EJECT__SANDBOX)/node_modules/.cache/_esy/store/${Config.STORE_STAGE_TREE}`,
      ],
    },
    {
      type: 'rule',
      target: '$(ESY_EJECT__ROOT)/bin/realpath',
      dependencies: ['$(ESY_EJECT__ROOT)/bin/realpath.c'],
      shell: '/bin/bash',
      command: 'gcc -o $(@) -x c $(<) 2> /dev/null',
    },
    {
      type: 'rule',
      target: '$(ESY_EJECT__ROOT)/bin/fastreplacestring.exe',
      dependencies: ['$(ESY_EJECT__ROOT)/bin/fastreplacestring.cpp'],
      shell: '/bin/bash',
      command: 'g++ -Ofast -o $(@) $(<) 2> /dev/null',
    },
    {
      type: 'rule',
      target: 'esy-root',
      phony: true,
      dependencies: [
        '$(ESY_EJECT__ROOT)/bin/realpath',
        '$(ESY_EJECT__ROOT)/bin/fastreplacestring.exe',
      ],
    },
  ];

  function createBuildRuleName(build, target): string {
    return `${build.name}.${target}`;
  }

  function createBuildRule(
    build: BuildSpec,
    rule: {target: string, command: string, withBuildEnv?: boolean},
  ): Makefile.MakeItem {
    const command = [];
    if (rule.withBuildEnv) {
      command.push(
        outdent`
          $(shell_env_for__${normalizePackageName(build.name)}) source $(ESY_EJECT__ROOT)/bin/runtime.sh
          cd $esy_build__source_root
        `,
      );
    }
    command.push(rule.command);
    return {
      type: 'rule',
      target: createBuildRuleName(build, rule.target),
      dependencies: [
        'esy-store',
        'esy-root',
        ...Array.from(build.dependencies.values()).map(dep =>
          createBuildRuleName(dep, 'build'),
        ),
      ],
      phony: true,
      command,
    };
  }

  function visitTask(task: BuildTask) {
    log(`visit ${task.spec.name}`);

    const packagePath = task.spec.sourcePath.split(path.sep).filter(Boolean);

    function emitBuildFile({filename, contents}) {
      emitFile(outputPath, {filename: packagePath.concat(filename), contents});
    }

    // Emit env
    emitBuildFile({
      filename: 'eject-env',
      contents: renderEnv(task.env),
    });

    // Generate macOS sandbox configuration (sandbox-exec command)
    emitBuildFile({
      filename: 'sandbox.sb.in',
      contents: renderSandboxSbConfig(task.spec, buildConfig, {
        allowFileWrite: ['$TMPDIR', '$TMPDIR_GLOBAL'],
      }),
    });

    ruleSet.push({
      type: 'define',
      name: `shell_env_for__${normalizePackageName(task.spec.name)}`,
      value: [
        {
          CI: process.env.CI ? process.env.CI : null,
          TMPDIR: '$(TMPDIR)',
          ESY_EJECT__STORE: '$(ESY_EJECT__STORE)',
          ESY_EJECT__SANDBOX: '$(ESY_EJECT__SANDBOX)',
          ESY_EJECT__ROOT: '$(ESY_EJECT__ROOT)',
        },
        `source $(ESY_EJECT__ROOT)/${packagePath.join('/')}/eject-env`,
        {
          esy_build__eject: `$(ESY_EJECT__ROOT)/${packagePath.join('/')}`,
          esy_build__type: task.spec.mutatesSourcePath ? 'in-source' : 'out-of-source',
          esy_build__key: task.id,
          esy_build__command: renderBuildTaskCommand(task) || 'true',
          esy_build__source_root: path.join(
            buildConfig.sandboxPath,
            task.spec.sourcePath,
          ),
          esy_build__install: buildConfig.getFinalInstallPath(task.spec),
        },
      ],
    });

    ruleSet.push(
      createBuildRule(task.spec, {
        target: 'build',
        command: 'esy-build',
        withBuildEnv: true,
      }),
    );
    ruleSet.push(
      createBuildRule(task.spec, {
        target: 'shell',
        command: 'esy-shell',
        withBuildEnv: true,
      }),
    );
    ruleSet.push(
      createBuildRule(task.spec, {
        target: 'clean',
        command: 'esy-clean',
      }),
    );
  }

  // Emit build artefacts for packages
  log('process dependency graph');
  const rootTask = Task.fromBuildSandbox(sandbox, buildConfig);
  Graph.traverse(rootTask, visitTask);

  // Now emit all build-wise artefacts
  log('build environment');

  emitFile(outputPath, {
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
  });

  emitFile(outputPath, {
    filename: ['bin', 'fastreplacestring.cpp'],
    contents: fastReplaceStringSrc,
  });

  emitFile(outputPath, {
    filename: ['bin', 'realpath.c'],
    contents: outdent`
      #include<stdlib.h>

      main(int cc, char**vargs) {
        puts(realpath(vargs[1], 0));
        exit(0);
      }
    `,
  });

  emitFile(outputPath, {
    filename: ['bin', 'runtime.sh'],
    contents: RUNTIME,
  });

  emitFile(outputPath, {
    filename: ['Makefile'],
    contents: Makefile.renderMakefile(ruleSet),
  });
}

function emitFile(
  outputPath: string,
  file: {filename: Array<string>, contents: string, executable?: boolean},
) {
  const filename = path.join(outputPath, ...file.filename);
  log(`emit <ejectRootDir>/${file.filename.join('/')}`);
  mkdirp(path.dirname(filename));
  fs.writeFileSync(filename, file.contents);
  if (file.executable) {
    // fs.constants only became supported in node 6.7 or so.
    const mode = fs.constants && fs.constants.S_IRWXU ? fs.constants.S_IRWXU : 448;
    fs.chmodSync(filename, mode);
  }
}

function renderBuildTaskCommand(task: BuildTask): ?string {
  if (task.command == null) {
    return null;
  }
  return task.command.map(c => c.renderedCommand).join(' && ');
}
