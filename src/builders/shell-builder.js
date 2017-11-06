/**
 * @flow
 */

import type {BuildTask, BuildTaskCommand, BuildSandbox, Config} from '../types';

import * as os from 'os';
import outdent from 'outdent';
import createLogger from 'debug';

import * as path from '../lib/path';
import * as fs from '../lib/fs';
import {singleQuote} from '../lib/shell';
import * as environment from '../environment';
import * as Graph from '../graph';
import {renderSandboxSbConfig} from './util';
import {defineScriptDir} from './bashgen';
import {renderEnv} from '../Makefile';
import {renderBuildTaskCommand} from './makefile-builder';

const log = createLogger('esy:shell-builder');

const RUNTIME = fs.readFileSync(require.resolve('./shell-builder.sh'));

export const eject = async (
  outputPath: string,
  task: BuildTask,
  sandbox: BuildSandbox,
  config: Config<path.AbsolutePath>,
) => {
  const transientTasks = [];
  Graph.traverse(task, task => {
    if (task.spec.sourceType === 'transient') {
      transientTasks.push(task);
    }
  });

  const esyBuildWrapperEnv = {
    ESY_EJECT__ROOT: outputPath,
    ESY_SANDBOX: config.sandboxPath,
  };

  const esyBuildEnv = {
    ESY_EJECT__ROOT: outputPath,
    esy_build__sandbox_config_darwin: path.join('$ESY_EJECT__ROOT', 'bin', 'sandbox.sb'),
    esy_build__source_root: path.join(config.sandboxPath, task.spec.sourcePath),
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
    filename: ['bin/runtime.sh'],
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

  const checkDependencies = await Promise.all(
    transientTasks.map(async t => {
      const installPath = config.getFinalInstallPath(t.spec);
      const prevMtimePath = config.getBuildPath(t.spec, '_esy', 'mtime');
      const sourcePath = await fs.realpath(config.getSourcePath(t.spec));
      return outdent`
      if [ ! -d "${installPath}" ]; then
        buildDependencies I
        return
      fi

      if [ ! -f "${prevMtimePath}" ]; then
        buildDependencies B
        return
      fi

      prevMtime=$(cat "${prevMtimePath}")
      curMtime=$(findMaxMtime "${sourcePath}")
      if [ "$curMtime" -gt "$prevMtime" ]; then
        buildDependencies MTIME
        return
      fi
    `;
    }),
  );

  await emitFile({
    filename: ['bin/build-dependencies'],
    executable: true,
    contents: outdent`
      #!/bin/bash

      set -e
      set -o pipefail

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
        (cd "$ESY_SANDBOX" && \
         "${process.argv[0]}" "${process.argv[1]}" build --dependencies-only)
      }

      findMaxMtime () {
        local root="$1"
        local maxMtime
        maxMtime=$(
          find "$root" \
          -not -path "$root/node_modules/*" -a \
          -not -path "$root/node_modules" -a \
          -not -path "$root/_build" -a \
          -not -path "$root/_install" -a \
          -not -path "$root/_esy" -a \
          -not -path "$root/_release" -a \
          -exec $getMtime {} \\; | sort -r | head -n1)
        echo "$maxMtime"
      }

      checkDependencies () {
        ${checkDependencies.length > 0 ? checkDependencies.join('') : 'true'}
      }

      checkDependencies
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
      exec env -i /bin/bash "$ESY_EJECT__ROOT/bin/_build" "$@"
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
      exec env -i /bin/bash "$ESY_EJECT__ROOT/bin/_shell" "$@"
    `,
  });

  await emitFile({
    filename: ['bin/_build'],
    contents: outdent`
      set -e
      set -o pipefail

      ${renderEnv(esyBuildEnv)}

      source "$ESY_EJECT__ROOT/bin/build-env"
      source "$ESY_EJECT__ROOT/bin/runtime.sh"

      if [ $# -eq 0 ]; then
        esyPerformBuild
      else
        esyExecCommand "$@"
      fi
    `,
  });

  await emitFile({
    filename: ['bin/_shell'],
    contents: outdent`

      ${renderEnv(esyBuildEnv)}

      source "$ESY_EJECT__ROOT/bin/build-env"
      source "$ESY_EJECT__ROOT/bin/runtime.sh"

      esyShell
    `,
  });
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
