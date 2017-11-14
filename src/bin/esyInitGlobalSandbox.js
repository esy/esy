/**
 * @flow
 */

import type {CommandContext, CommandInvocation} from './esy';

import {getSandbox, getBuildConfig} from './esy';
import {handleFinalBuildState, createBuildProgressReporter} from './esyBuild';
import * as GlobalSandbox from '../sandbox/global-sandbox';
import * as S from '../sandbox';
import * as E from '../environment';
import * as T from '../build-task';
import * as B from '../builders/simple-builder';
import * as path from '../lib/path';
import * as ShellBuilder from '../builders/shell-builder';

export default async function esyInitGlobalSandbox(
  ctx: CommandContext,
  invocation: CommandInvocation,
) {
  const [outputPath] = invocation.args;
  if (outputPath == null) {
    ctx.error('provide path for the ejected sandbox');
  }

  const requests = toArray(invocation.options.options.require);
  const config = await getBuildConfig(ctx);
  const sandbox = await GlobalSandbox.create(outputPath, requests, config);
  const task = T.fromSandbox(sandbox, config);

  const buildDependencies = handleFinalBuildState(
    ctx,
    B.buildDependencies(task, config, createBuildProgressReporter()),
  );

  const ejectSandbox = ShellBuilder.eject(
    path.join(outputPath, 'build'),
    task,
    sandbox,
    config,
  );

  await Promise.all([buildDependencies, ejectSandbox]);
}

export const options = {
  options: ['-r', '--require'],
  alias: {
    '-r': 'require',
  },
};

function toArray(v) {
  return [].concat(v);
}
