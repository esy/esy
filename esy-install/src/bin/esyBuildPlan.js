/**
 * @flow
 */

const path = require('path');
import * as types from '../types.js';
import type {CommandContext, CommandInvocation} from './esy.js';

import {getSandbox, getBuildConfig} from './esy';
import * as Sandbox from '../sandbox';
import * as Env from '../environment';
import * as Task from '../build-task';
import * as Config from '../config';
import * as shell from '../lib/shell.js';
import * as json from '../lib/json.js';

export default async function esyPlan(ctx: CommandContext, {args}: CommandInvocation) {
  function findTaskByPackagePath(tasks: Array<types.BuildTask>, packagePath) {
    const predicate = task =>
      path.join(config.sandboxPath, task.spec.packagePath) === packagePath;
    const queue: types.BuildTask[] = [...tasks];
    while (queue.length > 0) {
      const t = queue.shift();
      if (predicate(t)) {
        return t;
      }
      queue.push(...t.dependencies.values());
    }

    return ctx.error(
      `unable to plan the build for ${packagePath}: no such package found`,
    );
  }

  const sandbox = await getSandbox(ctx);
  const config = Config.create({
    reporter: ctx.reporter,
    storePath: '%store%',
    sandboxPath: '%sandbox%',
    buildPlatform: ctx.buildPlatform,
  });
  const [packagePath] = args;
  let task = Task.fromSandbox(sandbox, config);
  if (packagePath != null) {
    const devDependencies = Array.from(sandbox.devDependencies.values(), spec =>
      Task.fromBuildSpec(spec, config, {env: sandbox.env}),
    );
    task = findTaskByPackagePath(
      [task, ...devDependencies],
      path.join(config.sandboxPath, packagePath),
    );
  }

  console.log(json.stableStringifyPretty(Task.exportBuildTask(task)));
}

export const noHeader = true;
