/**
 * @flow
 */

import type {BuildTask, BuildTaskCommand, Sandbox, Config} from '../types';

import * as os from 'os';
import outdent from 'outdent';
import createLogger from 'debug';

import * as path from '../lib/path';
import * as fs from '../lib/fs';
import * as child from '../lib/child_process';
import {singleQuote} from '../lib/shell';
import * as environment from '../environment';
import * as Graph from '../graph';
import {renderSandboxSbConfig} from './util';
import {defineScriptDir} from './bashgen';
import {renderEnv} from '../Makefile';
import * as S from '../sandbox';
import * as T from '../build-task';
import {renderBuildTaskCommand} from './makefile-builder';

const log = createLogger('esy:shell-builder');

const RUNTIME = fs.readFileSync(require.resolve('./shell-builder.sh'));

function collectDependencies(root, immutableDeps, transientDeps) {
  Graph.traverse(root, task => {
    switch (task.spec.sourceType) {
      case 'transient':
        transientDeps.set(task.id, task);
        break;
      case 'immutable':
        immutableDeps.set(task.id, task);
        break;
    }
  });
}

export const eject = async (
  outputPath: string,
  task: BuildTask,
  sandbox: Sandbox,
  config: Config<path.AbsolutePath>,
) => {
  const immutableDeps = new Map();
  const transientDeps = new Map();

  collectDependencies(task, immutableDeps, transientDeps);
  for (const devDep of sandbox.devDependencies.values()) {
    const task = T.fromBuildSpec(devDep, config);
    collectDependencies(task, immutableDeps, transientDeps);
  }

  const esyBuildWrapperEnv = {
    ESY_EJECT__ROOT: outputPath,
    ESY_EJECT__STORE: config.store.path,
    ESY_SANDBOX: config.sandboxPath,
  };

  const esyBuildEnv = {
    ESY_EJECT__ROOT: outputPath,
    ESY_EJECT__STORE: config.store.path,
    esy_build__sandbox_config_darwin: path.join('$ESY_EJECT__ROOT', 'bin', 'sandbox.sb'),
    esy_build__source_root: config.getSourcePath(task.spec),
    esy_build__install_root: config.getFinalInstallPath(task.spec),
    esy_build__build_type: task.spec.buildType,
    esy_build__source_type: task.spec.sourceType,
    esy_build__build_command: renderBuildTaskCommand(task.buildCommand),
    esy_build__install_command: renderBuildTaskCommand(task.installCommand),
  };

  const emitFile = (file: File) => emitFileInto(outputPath, file);

  await fs.rmdir(outputPath);

  await emitFile({
    filename: ['bin/build-env'],
    contents: environment.printEnvironment(task.env),
  });

  await emitFile({
    filename: ['bin/command-env'],
    contents: environment.printEnvironment(S.getCommandEnv(sandbox, config)),
  });

  await emitFile({
    filename: ['bin/command-exec'],
    executable: true,
    contents: outdent`
      ${environment.printEnvironment(S.getCommandEnv(sandbox, config))}
      exec "$@"
    `,
  });

  await emitFile({
    filename: ['bin/sandbox-env'],
    contents: environment.printEnvironment(S.getSandboxEnv(sandbox, config)),
  });

  await emitFile({
    filename: ['bin/shell-builder.sh'],
    contents: RUNTIME,
  });

  const tempDirs: Array<Promise<?string>> = ['/tmp', process.env.TMPDIR]
    .filter(Boolean)
    .map(p => fs.realpath(p));

  await emitFile({
    filename: ['bin/sandbox.sb'],
    contents: renderSandboxSbConfig(task.spec, config, {
      allowFileWrite: await Promise.all(tempDirs),
    }),
  });

  const checkImmutableDeps = Array.from(immutableDeps.values()).map(t => {
    const installPath = config.getFinalInstallPath(t.spec);
    return outdent`
      if [ ! -d "${installPath}" ]; then
        buildDependencies "$@"
        return
      fi
    `;
  });

  const checkTransientDeps = await Promise.all(
    Array.from(transientDeps.values()).map(async t => {
      const installPath = config.getFinalInstallPath(t.spec);
      const prevMtimePath = config.getBuildPath(t.spec, '_esy', 'mtime');
      const sourcePath = config.getSourcePath(t.spec);
      return outdent`

      if [ ! -d "${installPath}" ]; then
        buildDependencies "$@"
        return
      fi

      if [ "$performStalenessCheck" == "yes" ]; then

        if [ "$ESY__LOG_ACTION" == "yes" ]; then
          echo "# ACTION: build-dependencies: staleness check ${t.spec.packagePath}"
        fi

        if [ ! -f "${prevMtimePath}" ]; then
          buildDependencies "$@"
          return
        fi

        prevMtime=$(cat "${prevMtimePath}")
        curMtime=$(findMaxMtime "${sourcePath}")
        if [ "$curMtime" -gt "$prevMtime" ]; then
          buildDependencies "$@"
          return
        fi

      fi
    `;
    }),
  );

  const nodeCmd = process.argv[0];
  const esyCmd = process.argv[1];

  await emitFile({
    filename: ['bin/build-dependencies'],
    executable: true,
    contents: outdent`
      #!/bin/bash

      set -e
      set -o pipefail

      performStalenessCheck="yes"

      if [ "$1" == "--ignore-staleness-check" ]; then
        performStalenessCheck="no"
        shift
      fi

      if [ "$ESY__LOG_ACTION" == "yes" ]; then
        echo "# ACTION: build-dependencies: checking if dependencies are built"
      fi

      ${renderEnv(esyBuildWrapperEnv)}

      # Configure sandbox mechanism
      getMtime="stat -c %Y"
      case $(uname) in
        Darwin*)
          getMtime="stat -f %m"
          ;;
        Linux*)
          ;;
        MSYS*);;
        *);;
      esac

      buildDependencies () {
        if [ "$1" == "--silent" ]; then
          (>&2 echo "info: rebuilding project, this will take some time...")
        fi
        (cd "$ESY_SANDBOX" && \
         "${nodeCmd}" "${esyCmd}" "$@" build --dependencies-only --eject "${outputPath}")
      }

      findMaxMtime () {
        local root="$1"
        local maxMtime
        maxMtime=$(
          find "$root" \
          -type f -a \
          -not -name ".merlin" -a \
          -not -name "*.install" -a \
          -not -path "$root/node_modules/*" -a \
          -not -path "$root/node_modules" -a \
          -not -path "$root/_build" -a \
          -not -path "$root/_install" -a \
          -not -path "$root/_esy" -a \
          -not -path "$root/_release" \
          -exec $getMtime {} \\; | sort -r | head -n1)
        echo "$maxMtime"
      }

      checkDependencies () {
        ${checkTransientDeps.length > 0 ? checkTransientDeps.join('\n') : 'true'}
        ${checkImmutableDeps.length > 0 ? checkImmutableDeps.join('\n') : 'true'}
      }

      checkDependencies "$@"
    `,
  });

  await emitFile({
    filename: ['bin/build'],
    executable: true,
    contents: outdent`
      #!/bin/bash

      set -e
      set -o pipefail

      ${renderEnv(esyBuildWrapperEnv)}

      $ESY_EJECT__ROOT/bin/build-dependencies
      exec env -i ESY__LOG_ACTION="$ESY__LOG_ACTION" /bin/bash "$ESY_EJECT__ROOT/bin/_build"
    `,
  });

  await emitFile({
    filename: ['bin/build-exec'],
    executable: true,
    contents: outdent`
      #!/bin/bash

      set -e
      set -o pipefail

      ${renderEnv(esyBuildWrapperEnv)}

      $ESY_EJECT__ROOT/bin/build-dependencies --silent
      exec env -i ESY__LOG_ACTION="$ESY__LOG_ACTION" /bin/bash "$ESY_EJECT__ROOT/bin/_build" "$@"
    `,
  });

  await emitFile({
    filename: ['bin/install'],
    executable: true,
    contents: outdent`
      #!/bin/bash

      set -e
      set -o pipefail

      ${renderEnv(esyBuildWrapperEnv)}

      $ESY_EJECT__ROOT/bin/build-dependencies --ignore-staleness-check
      exec env -i ESY__LOG_ACTION="$ESY__LOG_ACTION" /bin/bash "$ESY_EJECT__ROOT/bin/_install" "$@"
    `,
  });

  await emitFile({
    filename: ['bin/shell'],
    executable: true,
    contents: outdent`
      #!/bin/bash

      set -e
      set -o pipefail

      ${renderEnv(esyBuildWrapperEnv)}

      $ESY_EJECT__ROOT/bin/build-dependencies
      exec env -i ESY__LOG_ACTION="$ESY__LOG_ACTION" /bin/bash "$ESY_EJECT__ROOT/bin/_shell" "$@"
    `,
  });

  await emitFile({
    filename: ['bin/_build'],
    contents: outdent`
      set -e
      set -o pipefail

      ${renderEnv(esyBuildEnv)}

      source "$ESY_EJECT__ROOT/bin/build-env"
      source "$ESY_EJECT__ROOT/bin/shell-builder.sh"

      if [ $# -eq 0 ]; then
        esyWithBuildEnv esyRunBuildCommands
      else
        esyWithBuildEnv esyExecCommand "$@"
      fi
    `,
  });

  await emitFile({
    filename: ['bin/_install'],
    contents: outdent`
      set -e
      set -o pipefail

      ${renderEnv(esyBuildEnv)}

      source "$ESY_EJECT__ROOT/bin/build-env"
      source "$ESY_EJECT__ROOT/bin/shell-builder.sh"

      _makeBuild () {
        esyRunBuildCommands --silent
        esyRunInstallCommands --silent
      }

      if [ ! -d "$esy_build__install_root" ]; then
        esyWithBuildEnv _makeBuild
      fi
    `,
  });

  await emitFile({
    filename: ['bin/_shell'],
    contents: outdent`

      ${renderEnv(esyBuildEnv)}

      source "$ESY_EJECT__ROOT/bin/build-env"
      source "$ESY_EJECT__ROOT/bin/shell-builder.sh"

      esyShell
    `,
  });

  await emitFile({
    filename: ['bin/fastreplacestring.cpp'],
    contents: fs.readFileSync(require.resolve('fastreplacestring/fastreplacestring.cpp')),
  });

  await child.spawn('g++', [
    '-Ofast',
    '-o',
    path.join(outputPath, 'bin', 'fastreplacestring.exe'),
    path.join(outputPath, 'bin', 'fastreplacestring.cpp'),
  ]);
};

type File = {
  filename: Array<string>,
  contents: string,
  executable?: boolean,
};

async function emitFileInto(outputPath: string, file: File) {
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

function renderCommand(command: BuildTaskCommand) {
  return outdent`
    # ${command.command}
    ${command.renderedCommand}
  `;
}
