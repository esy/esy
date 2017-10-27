/**
 * @flow
 */

import type {CommandContext} from './esy';
import type {BuildTask} from '../types';

import {settings as configureObservatory} from 'observatory';
import chalk from 'chalk';
import outdent from 'outdent';

import * as fs from '../lib/fs';
import {indent, getBuildSandbox} from './esy';
import * as Task from '../build-task';
import * as Builder from '../builders/simple-builder';

export default async function buildCommand(ctx: CommandContext) {
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

  const sandbox = await getBuildSandbox(ctx.config.sandboxPath);
  const task: BuildTask = Task.fromBuildSandbox(sandbox, ctx.config);
  const failures = [];
  await Builder.build(task, sandbox, ctx.config, (task, status) => {
    if (status.state === 'in-progress') {
      getReporterFor(task).status('building...');
    } else if (status.state === 'success') {
      const {timeEllapsed} = status;
      if (timeEllapsed != null) {
        getReporterFor(task).done('BUILT').details(`in ${timeEllapsed / 1000}s`);
      } else if (!task.spec.shouldBePersisted) {
        getReporterFor(task).done('BUILT').details(`unchanged`);
      }
    } else if (status.state === 'failure') {
      failures.push({task, error: status.error});
      getReporterFor(task).fail('FAILED');
    }
  });
  for (const failure of failures) {
    const {error} = failure;
    if (error.logFilename) {
      const {logFilename} = (error: any);
      if (!failure.task.spec.shouldBePersisted) {
        const logContents = fs.readFileSync(logFilename);
        console.log(
          outdent`

            ${chalk.red('FAILED')} ${failure.task.spec.name}, see log for details:

            ${chalk.red(indent(logContents, '  '))}
            `,
        );
      } else {
        console.log(
          outdent`

            ${chalk.red('FAILED')} ${failure.task.spec.name}, see log for details:
              ${logFilename}

            `,
        );
      }
    } else {
      console.log(
        outdent`

        ${chalk.red('FAILED')} ${failure.task.spec.name}:
          ${failure.error}

        `,
      );
    }
  }

  if (failures.length > 0) {
    ctx.error('build failed');
  }
}
