/**
 * @flow
 */

import type {CommandContext, CommandInvocation} from './esy';

import {getSandbox, getBuildConfig} from './esy';
import {handleFinalBuildState, createBuildProgressReporter} from './esyBuild';
import * as S from '../sandbox';
import * as E from '../environment';
import * as T from '../build-task';
import * as B from '../builders/simple-builder';

export default async function esyX(ctx: CommandContext, invocation: CommandInvocation) {
  const packages = Array.isArray(invocation.options.options.package)
    ? invocation.options.options.package
    : [invocation.options.options.package];
  const config = await getBuildConfig(ctx);
  const sandbox = await S.fromRequest(config, {packageSet: packages}, process.cwd());
  const task = T.fromSandbox(sandbox, config);
  await handleFinalBuildState(
    ctx,
    B.buildDependencies(task, config, createBuildProgressReporter()),
  );
  const env = S.getCommandEnv(sandbox, config);
  console.log(E.printEnvironment(env));
}

export const options = {
  options: ['-p', '--package'],
  alias: {
    '-p': 'package',
  },
};
