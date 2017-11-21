/**
 * @flow
 */

import type {CommandContext, CommandInvocation} from './esy';
import type {Config, Reporter, BuildTask} from '../types';

import chalk from 'chalk';
import outdent from 'outdent';

import * as fs from '../lib/fs';
import * as path from '../lib/path';
import {indent, getSandbox, getBuildConfig} from './esy';
import * as Task from '../build-task';
import * as M from '../package-manifest';
import * as Builder from '../builders/simple-builder';
import * as ShellBuilder from '../builders/shell-builder';

export function reportBuildError(ctx: CommandContext, error: Builder.BuildError) {
  const {spec} = error.task;

  const banner = spec.sourcePath === '' ? spec.name : `${spec.name} (${spec.sourcePath})`;
  const debugCommand = `esy build-shell ${error.task.spec.sourcePath}`;

  if (error instanceof Builder.BuildCommandError) {
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
  } else if (error instanceof Builder.InternalBuildError) {
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
  const {manifest: {esy: {sandboxType}}} = await M.read(config.sandboxPath);
  const sandbox = await getSandbox(ctx, {sandboxType});
  const task: BuildTask = Task.fromSandbox(sandbox, config);

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
    handleFinalBuildState(ctx, build(task, config)),
    ejectingBuild,
  ]);

  // TODO: parallelize it
  for (const devDep of sandbox.devDependencies.values()) {
    const task = Task.fromBuildSpec(devDep, config, {env: sandbox.env});
    await handleFinalBuildState(ctx, Builder.build(task, config));
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
      reportBuildError(ctx, error);
    }
    ctx.error();
  }
}

export const options = {
  flags: ['--dependencies-only', '--silent'],
  options: ['--eject'],
};
