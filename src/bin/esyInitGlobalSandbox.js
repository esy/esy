/**
 * @flow
 */

import type {CommandContext, CommandInvocation} from './esy';

import {getSandbox, getBuildConfig} from './esy';
import {handleFinalBuildState} from './esyBuild';
import * as GlobalSandbox from '../sandbox/global-sandbox';
import * as C from '../config';
import * as S from '../sandbox';
import * as E from '../environment';
import * as T from '../build-task';
import * as B from '../builders/simple-builder';
import * as path from '../lib/path';
import * as BuildEnv from '../root-build-eject.js';

export default async function esyInitGlobalSandbox(
  ctx: CommandContext,
  invocation: CommandInvocation,
) {
  const [sandboxPath] = invocation.args;
  if (sandboxPath == null) {
    ctx.error('provide path for the ejected sandbox');
  }

  const request = toArray(invocation.options.options.require);

  const config = C.createForPrefix({
    reporter: ctx.reporter,
    prefixPath: ctx.prefixPath,
    sandboxPath,
    buildPlatform: ctx.buildPlatform,
    importPaths: ctx.importPaths,
  });

  await GlobalSandbox.initialize(sandboxPath, request, {
    installCachePath: path.join(ctx.prefixPath, 'install-cache'),
    reporter: config.reporter,
  });

  const sandbox = await GlobalSandbox.create(sandboxPath, {
    installCachePath: path.join(ctx.prefixPath, 'install-cache'),
    reporter: config.reporter,
  });

  const task = T.fromSandbox(sandbox, config);

  const buildDependencies = handleFinalBuildState(ctx, B.buildDependencies(task, config));

  const ejectSandbox = BuildEnv.eject(
    path.join(sandboxPath, 'build'),
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
