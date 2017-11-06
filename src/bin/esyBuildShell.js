/**
 * @flow
 */

import type {CommandContext} from './esy';
import type {BuildTask} from '../types';

import {settings as configureObservatory} from 'observatory';
import chalk from 'chalk';
import outdent from 'outdent';
import * as path from 'path';

import * as fs from '../lib/fs';
import {indent, getBuildSandbox, getBuildConfig} from './esy';
import * as Task from '../build-task';
import * as Builder from '../builders/simple-builder';
import {reportBuildError, createBuildProgressReporter} from './esyBuild';

export default async function esyBuildShell(ctx: CommandContext) {
  function findTaskBySourcePath(task: BuildTask, packageSourcePath) {
    const predicate = task =>
      path.join(config.sandboxPath, task.spec.sourcePath) === packageSourcePath;
    const queue: BuildTask[] = [task];
    while (queue.length > 0) {
      const t = queue.shift();
      if (predicate(t)) {
        return t;
      }
      queue.push(...t.dependencies.values());
    }

    return ctx.error(
      `unable to initialize build shell for ${packageSourcePath}: no such package found`,
    );
  }

  const [packageSourcePath] = ctx.args;

  const sandbox = await getBuildSandbox(ctx);
  const config = await getBuildConfig(ctx);

  const rootTask: BuildTask = Task.fromBuildSandbox(sandbox, config);

  const task =
    packageSourcePath != null
      ? findTaskBySourcePath(rootTask, path.resolve(process.cwd(), packageSourcePath))
      : rootTask;

  const reporter = createBuildProgressReporter();
  const state = await Builder.buildDependencies(task, config, reporter);
  if (state.state === 'failure') {
    const errors = Builder.collectBuildErrors(state);
    for (const error of errors) {
      reportBuildError(error);
    }
    ctx.error('build failed');
  }

  await Builder.withBuildDriver(task, config, async driver => {
    await driver.spawnInteractiveProcess('/bin/bash', []);
  });
}
