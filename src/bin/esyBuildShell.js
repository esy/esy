/**
 * @flow
 */

import type {CommandContext, CommandInvocation} from './esy';
import type {BuildTask} from '../types';

import {settings as configureObservatory} from 'observatory';
import chalk from 'chalk';
import outdent from 'outdent';
import * as path from 'path';

import * as fs from '../lib/fs';
import * as Task from '../build-task.js';
import {indent, getSandbox, getBuildConfig} from './esy';
import * as Builder from '../builders/simple-builder';
import {reportBuildError} from './esyBuild';

export default async function esyBuildShell(
  ctx: CommandContext,
  invocation: CommandInvocation,
) {
  function findTaskBySourcePath(tasks: Array<BuildTask>, packagePath) {
    const predicate = task =>
      path.join(config.sandboxPath, task.spec.packagePath) === packagePath;
    const queue: BuildTask[] = [...tasks];
    while (queue.length > 0) {
      const t = queue.shift();
      if (predicate(t)) {
        return t;
      }
      queue.push(...t.dependencies.values());
    }

    return ctx.error(
      `unable to initialize build shell for ${packagePath}: no such package found`,
    );
  }

  const [packagePath] = invocation.args;

  const sandbox = await getSandbox(ctx);
  const config = await getBuildConfig(ctx);

  const rootTask: BuildTask = Task.fromSandbox(sandbox, config);
  const devDependencies: Array<BuildTask> = Array.from(
    sandbox.devDependencies.values(),
    spec => Task.fromBuildSpec(spec, config, {env: sandbox.env}),
  );

  const task =
    packagePath != null
      ? findTaskBySourcePath(
          [rootTask, ...devDependencies],
          path.resolve(process.cwd(), packagePath),
        )
      : rootTask;

  const state = await Builder.buildDependencies(task, config);
  if (state.state === 'failure') {
    const errors = Builder.collectBuildErrors(state);
    for (const error of errors) {
      reportBuildError(ctx, error);
    }
    ctx.error('build failed');
  }

  await Builder.withBuildDriver(task, config, async driver => {
    await driver.spawnInteractiveProcess('/bin/bash', []);
  });
}
