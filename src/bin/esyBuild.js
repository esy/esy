/**
 * @flow
 */

import type {CommandContext} from './esy';
import type {BuildTask} from '../types';

import {settings as configureObservatory} from 'observatory';
import chalk from 'chalk';
import outdent from 'outdent';

import * as fs from '../lib/fs';
import {indent, getBuildSandbox, getBuildConfig} from './esy';
import * as Task from '../build-task';
import * as Builder from '../builders/simple-builder';

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
        getReporterFor(task)
          .done('BUILT')
          .details(`in ${timeEllapsed / 1000}s`);
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
  const banner = spec.sourcePath === '' ? spec.name : `${spec.name} (${spec.sourcePath})`;
  if (error instanceof Builder.BuildCommandError) {
    const {logFilename} = (error: any);
    if (!error.task.spec.shouldBePersisted) {
      const logContents = fs.readFileSync(logFilename);
      console.log(
        outdent`

        ${chalk.red('FAILED')} ${banner}
          The error happennded during execution of a build command, see log for details:

          ${chalk.red(indent(logContents, '  '))}
        `,
      );
    } else {
      console.log(
        outdent`

        ${chalk.red('FAILED')} ${banner}
          The error happennded during execution of a build command, see the log file for details:
          ${logFilename}

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

export default async function esyBuild(ctx: CommandContext) {
  const sandbox = await getBuildSandbox(ctx);
  const config = await getBuildConfig(ctx);
  const task: BuildTask = Task.fromBuildSandbox(sandbox, config);
  const reporter = createBuildProgressReporter();
  const state = await Builder.build(task, sandbox, config, reporter);
  if (state.state === 'failure') {
    const errors = Builder.collectBuildErrors(state);
    for (const error of errors) {
      reportBuildError(error);
    }
    ctx.error();
  }
}
