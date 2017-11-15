/**
 * @flow
 */

import type {CommandContext, CommandInvocation} from './esy';
import type {BuildTask} from '../types';

import {settings as configureObservatory} from 'observatory';
import chalk from 'chalk';
import outdent from 'outdent';

import * as fs from '../lib/fs';
import * as path from '../lib/path';
import {indent, getSandbox, getBuildConfig} from './esy';
import * as Task from '../build-task';
import * as M from '../package-manifest';
import * as Builder from '../builders/simple-builder';
import * as ShellBuilder from '../builders/shell-builder';

export function createBuildProgressReporter() {
  const observatory = configureObservatory({
    prefix: chalk.green('  → '),
  });

  const loggingHandlers = new Map();
  function getReporterFor(task) {
    let handler = loggingHandlers.get(task.id);
    if (handler == null) {
      const version = chalk.grey(`@ ${task.spec.version}`);
      handler = observatory.add(`${task.spec.name} ${version}`);
      loggingHandlers.set(task.id, handler);
    }
    return handler;
  }

  return (task: BuildTask, status: Builder.BuildState) => {
    if (status.state === 'in-progress') {
      getReporterFor(task).status('building...');
    } else if (status.state === 'success') {
      const {timeEllapsed} = status;
      if (timeEllapsed != null) {
        const timeEllapsedPretty =
          process.env.NODE_ENV === 'test' ? 'NNN' : String(timeEllapsed / 1000);
        getReporterFor(task)
          .done('BUILT')
          .details(`in ${timeEllapsedPretty}s`);
      } else if (!task.spec.shouldBePersisted) {
        getReporterFor(task)
          .done('BUILT')
          .details(`unchanged`);
      }
    } else if (status.state === 'failure') {
      getReporterFor(task).fail('FAILED');
    }
  };
}

export function reportBuildError(error: Builder.BuildError) {
  const {spec} = error.task;
  const banner = chalk.bold(
    spec.sourcePath === '' ? spec.name : `${spec.name} (${spec.sourcePath})`,
  );
  if (error instanceof Builder.BuildCommandError) {
    const {logFilename} = (error: any);
    if (!error.task.spec.shouldBePersisted || process.env.CI) {
      const logContents = fs.readFileSync(logFilename);
      console.log(
        outdent`

        ${chalk.red('FAILED')} ${banner}: build failed, see log:

        ${chalk.red(indent(logContents, '    '))}
          To get into the build environment and debug it:

            % esy build-shell ${error.task.spec.sourcePath}

        `,
      );
    } else {
      console.log(
        outdent`

        ${chalk.red('FAILED')} ${banner}
          The error happennded during execution of a build command, see the log file for details:

            ${logFilename}

          To get into the build environment and debug it:

            % esy build-shell ${error.task.spec.sourcePath}

        `,
      );
    }
  } else if (error instanceof Builder.InternalBuildError) {
    console.log(
      outdent`

      ${chalk.red('FAILED')} ${banner}
        The error below is likely a bug in Esy itself, please report it.

        ${chalk.red(error.error.stack)}

      `,
    );
  } else {
    console.log(
      outdent`

      ${chalk.red('FAILED')} ${banner}:
        The error below is likely a bug in Esy itself, please report it.

        ${chalk.red(error.stack)}

      `,
    );
  }
}

export default async function esyBuild(
  ctx: CommandContext,
  invocation: CommandInvocation,
) {
  const config = await getBuildConfig(ctx);
  const {manifest: {esy: {sandboxType}}} = await M.read(config.sandboxPath);
  const sandbox = await getSandbox(ctx, {sandboxType});
  const task: BuildTask = Task.fromSandbox(sandbox, config);
  const reporter = invocation.options.flags.silent
    ? undefined
    : createBuildProgressReporter();

  let ejectingBuild = null;
  if (invocation.options.options.eject != null) {
    ejectingBuild = ShellBuilder.eject(
      invocation.options.options.eject,
      task,
      sandbox,
      config,
    );
  }

  const build = invocation.options.flags.dependenciesOnly
    ? Builder.buildDependencies
    : Builder.build;

  const [state, _] = await Promise.all([
    handleFinalBuildState(ctx, build(task, config, reporter)),
    ejectingBuild,
  ]);

  // TODO: parallelize it
  for (const devDep of sandbox.devDependencies.values()) {
    const task = Task.fromBuildSpec(devDep, config, {env: sandbox.env});
    await handleFinalBuildState(ctx, Builder.build(task, config, reporter));
  }
}

export async function handleFinalBuildState(
  ctx: CommandContext,
  build: Promise<Builder.FinalBuildState>,
) {
  const state = await build;
  if (state.state === 'failure') {
    const errors = Builder.collectBuildErrors(state);
    for (const error of errors) {
      reportBuildError(error);
    }
    ctx.error();
  }
}

export const options = {
  flags: ['--dependencies-only', '--silent'],
  options: ['--eject'],
};
