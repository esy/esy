/**
 * @flow
 */

import type {BuildTask, BuildTaskCommand, Sandbox, Config} from './types';

import outdent from 'outdent';

import * as path from './lib/path';
import * as fs from './lib/fs';
import * as Env from './environment';
import * as Graph from './graph';
import {renderEnv} from './Makefile';
import * as S from './sandbox';
import * as C from './config';
import * as T from './build-task';
import * as json from './lib/json.js';

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
    const task = T.fromBuildSpec(devDep, config, {env: sandbox.env});
    collectDependencies(task, immutableDeps, transientDeps);
  }

  const esyBuildWrapperEnv = {
    ESY_EJECT__ROOT: outputPath,
    ESY_EJECT__STORE: config.store.path,
    ESY_SANDBOX: config.sandboxPath,
  };

  const emitFile = (file: File) => emitFileInto(outputPath, file);

  await fs.rmdir(outputPath);

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
    Array.from(transientDeps.values(), async t => {
      const buildJson = `$ESY_EJECT__ROOT/build/${t.spec.id}.json`;
      return outdent`
      ${C.ESYB_COMMAND} build -B ${buildJson}
    `;
    }),
  );

  const nodeCmd = process.argv[0];
  const esyCmd = process.argv[1];

  const ejects = [];

  for (const dep of transientDeps.values()) {
    ejects.push(
      emitFile({
        filename: [`build/${dep.spec.id}.json`],
        contents: json.stableStringifyPretty(T.exportBuildTask(config, dep)),
      }),
    );
  }

  ejects.push(
    emitFile({
      filename: [`build/${task.spec.id}.json`],
      contents: json.stableStringifyPretty(T.exportBuildTask(config, task)),
    }),

    emitFile({
      filename: ['bin/build-env'],
      contents: Env.printEnvironment(task.env),
    }),

    emitFile({
      filename: ['bin/command-env'],
      contents: Env.printEnvironment(S.getCommandEnv(sandbox, config)),
    }),

    emitFile({
      filename: ['bin/command-exec'],
      executable: true,
      contents: outdent`
      ${Env.printEnvironment(S.getCommandEnv(sandbox, config))}
      exec "$@"
    `,
    }),

    emitFile({
      filename: ['bin/sandbox-env'],
      contents: Env.printEnvironment(S.getSandboxEnv(sandbox, config)),
    }),

    emitFile({
      filename: ['bin/esyRuntime.sh'],
      contents: fs.readFileSync(require.resolve('../bin/esyRuntime.sh')),
    }),

    emitFile({
      filename: ['bin/realpath.sh'],
      contents: fs.readFileSync(require.resolve('../bin/realpath.sh')),
    }),

    emitFile({
      filename: ['bin/esyConfig.sh'],
      contents: fs.readFileSync(require.resolve('../bin/esyConfig.sh')),
    }),

    emitFile({
      filename: ['bin/build-dependencies'],
      executable: true,
      contents: outdent`
      #!/bin/bash

      set -e
      set -o pipefail

      BINDIR=$(dirname "$0")

      source "$BINDIR/realpath.sh"
      source "$BINDIR/esyConfig.sh"
      source "$BINDIR/esyRuntime.sh"

      esyLog "esy:build-dependencies" "checking if dependencies are built"

      ${renderEnv(esyBuildWrapperEnv)}

      buildDependencies () {
        if [ "$1" == "--silent" ]; then
          (>&2 echo "info: rebuilding project, this will take some time...")
        fi
        (cd "$ESY_SANDBOX" && \
         "${nodeCmd}" "${esyCmd}" "$@" build --dependencies-only --eject "${outputPath}")
      }

      checkDependencies () {
        ${checkTransientDeps.length > 0 ? checkTransientDeps.join('\n') : 'true'}
        ${checkImmutableDeps.length > 0 ? checkImmutableDeps.join('\n') : 'true'}
      }

      checkDependencies "$@"
    `,
    }),

    emitFile({
      filename: ['bin/build'],
      executable: true,
      contents: outdent`
      #!/bin/bash

      set -e
      set -o pipefail

      ${renderEnv(esyBuildWrapperEnv)}

      $ESY_EJECT__ROOT/bin/build-dependencies
      ${C.ESYB_COMMAND} build --quiet --build $ESY_EJECT__ROOT/build/${task.spec
        .id}.json --build-only --force
    `,
    }),

    emitFile({
      filename: ['bin/build-exec'],
      executable: true,
      contents: outdent`
      #!/bin/bash

      set -e
      set -o pipefail

      ${renderEnv(esyBuildWrapperEnv)}

      $ESY_EJECT__ROOT/bin/build-dependencies --silent
      ${C.ESYB_COMMAND} exec --build $ESY_EJECT__ROOT/build/${task.spec.id}.json -- "$@"
    `,
    }),

    emitFile({
      filename: ['bin/install'],
      executable: true,
      contents: outdent`
      #!/bin/bash

      set -e
      set -o pipefail

      ${renderEnv(esyBuildWrapperEnv)}

      $ESY_EJECT__ROOT/bin/build-dependencies
      ${C.ESYB_COMMAND} build --build $ESY_EJECT__ROOT/build/${task.spec.id}.json
    `,
    }),

    emitFile({
      filename: ['bin/shell'],
      executable: true,
      contents: outdent`
      #!/bin/bash

      set -e
      set -o pipefail

      ${renderEnv(esyBuildWrapperEnv)}

      $ESY_EJECT__ROOT/bin/build-dependencies
      ${C.ESYB_COMMAND} shell -B $ESY_EJECT__ROOT/build/${task.spec.id}.json
    `,
    }),
  );

  await Promise.all(ejects);
};

type File = {
  filename: Array<string>,
  contents: string,
  executable?: boolean,
};

async function emitFileInto(outputPath: string, file: File) {
  const filename = path.join(outputPath, ...file.filename);
  await fs.mkdirp(path.dirname(filename));
  await fs.writeFile(filename, file.contents);
  if (file.executable) {
    // fs.constants only became supported in node 6.7 or so.
    const mode = fs.constants && fs.constants.S_IRWXU ? fs.constants.S_IRWXU : 448;
    await fs.chmod(filename, mode);
  }
}
