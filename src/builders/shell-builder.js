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
  const emitFile = (file: File) => emitFileInto(outputPath, file);

  await fs.rmdir(outputPath);

  await emitFile({
    filename: ['build-env'],
    contents: environment.printEnvironment(task.env),
  });

  await emitFile({
    filename: ['runtime.sh'],
    contents: RUNTIME,
  });

  const tempDirs: Array<Promise<?string>> = ['/tmp', process.env.TMPDIR]
    .filter(Boolean)
    .map(p => fs.realpath(p));

  await emitFile({
    filename: ['sandbox.sb'],
    contents: renderSandboxSbConfig(task.spec, config, {
      allowFileWrite: await Promise.all(tempDirs),
    }),
  });

  await emitFile({
    filename: ['build'],
    executable: true,
    contents: outdent`
      #!/bin/bash

      set -e
      set -o pipefail

      ${defineScriptDir}

      exec env -i /bin/bash "$SCRIPTDIR/_build" "$@"
    `,
  });

  const sandboxPath = (...segments) => path.join(config.sandboxPath);

  const esyBuildEnv = {
    esy_build__sandbox_config_darwin: path.join('$SCRIPTDIR', 'sandbox.sb'),
    esy_build__source_root: path.join(config.sandboxPath, task.spec.sourcePath),
    esy_build__install_root: config.getFinalInstallPath(task.spec),
    esy_build__build_type: task.spec.buildType,
    esy_build__source_type: task.spec.sourceType,
    esy_build__build_command: renderBuildTaskCommand(task.buildCommand),
    esy_build__install_command: renderBuildTaskCommand(task.installCommand),
  };

  await emitFile({
    filename: ['_build'],
    contents: outdent`
      set -e
      set -o pipefail

      ${defineScriptDir}

      source "$SCRIPTDIR/build-env"

      ${renderEnv(esyBuildEnv)}

      source "$SCRIPTDIR/runtime.sh"

      if [ $# -eq 0 ]; then
        esyPerformBuild
      else
        esyExecCommand "$@"
      fi
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
