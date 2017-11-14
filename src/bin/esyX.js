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

export default async function esyX(ctx: CommandContext, invocation: CommandInvocation) {
  const requests = toArray(invocation.options.options.request);
  const config = await getBuildConfig(ctx);
  const sandbox = await GlobalSandbox.fromRequest(requests, config);
  const task = T.fromSandbox(sandbox, config);
  await handleFinalBuildState(
    ctx,
    B.buildDependencies(task, config, createBuildProgressReporter()),
  );
  const env = S.getCommandEnv(sandbox, config);
  console.log(E.printEnvironment(env));
}

export const options = {
  options: ['-r', '--request'],
  alias: {
    '-r': 'request',
  },
};

function toArray(v) {
  return [].concat(v);
}
