/**
 * @flow
 */

import type {CommandContext, CommandInvocation} from './esy';
import type {Config, Reporter, BuildTask} from '../types';

import chalk from 'chalk';
import outdent from 'outdent';
import createLogger from 'debug';

import * as fs from '../lib/fs';
import * as path from '../lib/path';
import {indent, getSandbox, getBuildConfig} from './esy';
import * as Task from '../build-task';
import * as M from '../package-manifest';
import * as B from '../build';
import * as RootBuildEject from '../root-build-eject.js';

const log = createLogger('esy:bin:esyBuild');

export function reportBuildError(ctx: CommandContext, error: B.BuildError) {
  const {spec} = error.task;

  const banner =
    spec.packagePath === '' ? spec.name : `${spec.name} (${spec.packagePath})`;
  const debugCommand = `esy build-shell ${error.task.spec.packagePath}`;

  if (error instanceof B.BuildCommandError) {
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
  } else if (error instanceof B.InternalBuildError) {
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

export default async function esyBuild(
  ctx: CommandContext,
  invocation: CommandInvocation,
) {
  const config = await getBuildConfig(ctx);
  const sandbox = await getSandbox(ctx);
  const task: BuildTask = Task.fromSandbox(sandbox, config);

  let ejectingBuild = null;
  if (invocation.options.options.eject != null) {
    ejectingBuild = RootBuildEject.eject(
      invocation.options.options.eject,
      task,
      sandbox,
      config,
    );
  }

  log('execute');

  const build = invocation.options.flags.dependenciesOnly ? B.buildDependencies : B.build;

  const [state, _] = await Promise.all([
    handleFinalBuildState(ctx, build(task, config)),
    ejectingBuild,
  ]);

  // TODO: parallelize it
  for (const devDep of sandbox.devDependencies.values()) {
    const task = Task.fromBuildSpec(devDep, config, {env: sandbox.env});
    await handleFinalBuildState(ctx, B.build(task, config));
  }
}

export async function handleFinalBuildState(
  ctx: CommandContext,
  build: Promise<B.FinalBuildState>,
) {
  const state = await build;
  if (state.state === 'failure') {
    const errors = B.collectBuildErrors(state);
    for (const error of errors) {
      reportBuildError(ctx, error);
    }
    ctx.error();
  }
}

export const options = {
  flags: ['--dependencies-only', '--silent'],
  options: ['--eject'],
};
