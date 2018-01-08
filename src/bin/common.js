/**
 * Common utilities shared between command impementations.
 *
 * @flow
 */

import * as t from '../types.js';
import type {CommandContext} from './esy.js';
import outdent from 'outdent';
import {indent} from './esy';
import * as chalk from 'chalk';
import * as Env from '../environment.js';
import * as constants from '../constants.js';
import * as BuildTask from '../build-task.js';
import * as Build from '../build.js';
import * as Sandbox from '../sandbox';
import * as Config from '../config.js';
import * as Graph from '../lib/graph.js';
import * as JSON from '../lib/json.js';
import * as fs from '../lib/fs.js';
import * as shell from '../lib/shell.js';
import * as path from '../lib/path.js';
import * as child from '../lib/child_process.js';

/**
 * Build sandbox
 */
export async function build(
  ctx: CommandContext,
  config: t.Config<*>,
  sandbox: t.Sandbox,
  options?: {buildRoot?: boolean, buildDevDependencies?: boolean} = {},
) {
  function reportBuildError(ctx: CommandContext, error: Build.BuildError) {
    const {spec} = error.task;

    const banner =
      spec.packagePath === '' ? spec.name : `${spec.name} (${spec.packagePath})`;
    const debugCommand = `esy build-shell ${error.task.spec.packagePath}`;

    if (error instanceof Build.BuildCommandError) {
      const {logFilename} = (error: any);
      if (error.task.spec.sourceType !== 'immutable' || process.env.CI) {
        const logContents = fs.readFileSync(logFilename);
        ctx.reporter.error(outdent`
        ${banner} failed to build, see log:

        ${chalk.red(indent(logContents, '    '))}
          To get into the build environment and debug it:

            % ${chalk.bold(debugCommand)}

        `);
      } else {
        ctx.reporter.error(
          outdent`
          ${banner} failed to build, see log for details:

            ${chalk.bold(logFilename)}

          To get into the build environment and debug it:

            % ${chalk.bold(debugCommand)}

        `,
        );
      }
    } else if (error instanceof Build.InternalBuildError) {
      ctx.reporter.error(
        outdent`
        ${banner} failed to build.

        The error below is likely a bug in Esy itself, please report it.

          ${chalk.red(error.error.stack)}

      `,
      );
    } else {
      ctx.reporter.error(
        outdent`
        ${banner} failed to build.

        The error below is likely a bug in Esy itself, please report it.

          ${chalk.red(error.stack)}

      `,
      );
    }
  }

  async function handleFinalBuildState(build: Promise<Build.FinalBuildState>) {
    const state = await build;
    if (state.state === 'failure') {
      const errors = Build.collectBuildErrors(state);
      for (const error of errors) {
        reportBuildError(ctx, error);
      }
      ctx.error();
    }
  }

  const {buildRoot = true, buildDevDependencies = true} = options;

  await Build.buildSession(config, async buildTask => {
    const tasks = [];

    if (buildRoot) {
      tasks.push(Build.build(buildTask, BuildTask.fromSandbox(sandbox, config), config));
    } else {
      tasks.push(
        Build.buildDependencies(
          buildTask,
          BuildTask.fromSandbox(sandbox, config),
          config,
        ),
      );
    }

    if (buildDevDependencies) {
      for (const devDep of sandbox.devDependencies.values()) {
        tasks.push(
          Build.build(
            buildTask,
            BuildTask.fromBuildSpec(devDep, config, {env: sandbox.env}),
            config,
          ),
        );
      }
    }

    await Promise.all(tasks.map(handleFinalBuildState));
  });
}

export async function ejectRootBuild(
  _ctx: CommandContext,
  config: t.Config<path.AbsolutePath>,
  sandbox: t.Sandbox,
  outputPath: string,
) {
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

  const task = BuildTask.fromSandbox(sandbox, config);
  const taskFilename = `$ESY_EJECT__ROOT/build/${task.spec.id}.json`;

  const immutableDeps = new Map();
  const transientDeps = new Map();

  collectDependencies(task, immutableDeps, transientDeps);
  for (const devDep of sandbox.devDependencies.values()) {
    const task = BuildTask.fromBuildSpec(devDep, config, {env: sandbox.env});
    collectDependencies(task, immutableDeps, transientDeps);
  }

  const esyBuildWrapperEnv = outdent`
    export ESY_EJECT__ROOT=${shell.doubleQuote(outputPath)};
    export ESY_EJECT__STORE=${shell.doubleQuote(config.store.path)};
    export ESY_SANDBOX=${shell.doubleQuote(config.sandboxPath)};
  `;

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
        ${Config.OCAMLRUN_COMMAND} ${Config.ESY_BUILD_PACKAGE_COMMAND} build -B ${buildJson}
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
        contents: JSON.stableStringifyPretty(BuildTask.exportBuildTask(config, dep)),
      }),
    );
  }

  ejects.push(
    emitFile({
      filename: [`build/${task.spec.id}.json`],
      contents: JSON.stableStringifyPretty(BuildTask.exportBuildTask(config, task)),
    }),

    emitFile({
      filename: ['bin/build-env'],
      contents: Env.printEnvironment(task.env),
    }),

    emitFile({
      filename: ['bin/command-env'],
      contents: Env.printEnvironment(Sandbox.getCommandEnv(sandbox, config)),
    }),

    emitFile({
      filename: ['bin/command-exec'],
      executable: true,
      contents: outdent`
      ${Env.printEnvironment(Sandbox.getCommandEnv(sandbox, config))}
      exec "$@"
    `,
    }),

    emitFile({
      filename: ['bin/sandbox-env'],
      contents: Env.printEnvironment(Sandbox.getSandboxEnv(sandbox, config)),
    }),

    emitFile({
      filename: ['bin/esyRuntime.sh'],
      contents: fs.readFileSync(require.resolve('../../bin/esyRuntime.sh')),
    }),

    emitFile({
      filename: ['bin/realpath.sh'],
      contents: fs.readFileSync(require.resolve('../../bin/realpath.sh')),
    }),

    emitFile({
      filename: ['bin/esyConfig.sh'],
      contents: fs.readFileSync(require.resolve('../../bin/esyConfig.sh')),
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

      ${esyBuildWrapperEnv}

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

      ${esyBuildWrapperEnv}

      $ESY_EJECT__ROOT/bin/build-dependencies
      ${Config.OCAMLRUN_COMMAND} ${Config.ESY_BUILD_PACKAGE_COMMAND} build --quiet --build ${taskFilename} --build-only --force
    `,
    }),

    emitFile({
      filename: ['bin/build-exec'],
      executable: true,
      contents: outdent`
      #!/bin/bash

      set -e
      set -o pipefail

      ${esyBuildWrapperEnv}

      $ESY_EJECT__ROOT/bin/build-dependencies --silent
      ${Config.OCAMLRUN_COMMAND} ${Config.ESY_BUILD_PACKAGE_COMMAND} exec --build ${taskFilename} -- "$@"
    `,
    }),

    emitFile({
      filename: ['bin/install'],
      executable: true,
      contents: outdent`
      #!/bin/bash

      set -e
      set -o pipefail

      ${esyBuildWrapperEnv}

      $ESY_EJECT__ROOT/bin/build-dependencies
      if [ ! -d "${config.getFinalInstallPath(task.spec)}" ]; then
        ${Config.OCAMLRUN_COMMAND} ${Config.ESY_BUILD_PACKAGE_COMMAND} build --build ${taskFilename} --force
      fi
    `,
    }),

    emitFile({
      filename: ['bin/shell'],
      executable: true,
      contents: outdent`
      #!/bin/bash

      set -e
      set -o pipefail

      ${esyBuildWrapperEnv}

      $ESY_EJECT__ROOT/bin/build-dependencies
      ${Config.OCAMLRUN_COMMAND} ${Config.ESY_BUILD_PACKAGE_COMMAND} shell -B ${taskFilename}
    `,
    }),
  );

  await Promise.all(ejects);
}

export async function exportBuild(
  ctx: CommandContext,
  config: t.Config<path.AbsolutePath>,
  build: t.BuildSpec,
  outputPath?: string,
) {
  const finalInstallPath = config.getFinalInstallPath(build);
  const args = ['export-build', finalInstallPath];
  if (outputPath != null) {
    args.push(outputPath);
  }
  await child.spawn(constants.CURRENT_ESY_EXECUTABLE, args, {stdio: 'inherit'});
}

type File = {
  filename: Array<string>,
  contents: string,
  executable?: boolean,
};

export async function emitFileInto(outputPath: string, file: File) {
  const filename = path.join(outputPath, ...file.filename);
  await fs.mkdirp(path.dirname(filename));
  await fs.writeFile(filename, file.contents);
  if (file.executable) {
    // fs.constants only became supported in node 6.7 or so.
    const mode = fs.constants && fs.constants.S_IRWXU ? fs.constants.S_IRWXU : 448;
    await fs.chmod(filename, mode);
  }
}
