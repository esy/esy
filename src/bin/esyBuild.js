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
import * as Common from './common.js';

const log = createLogger('esy:bin:esyBuild');

export default async function esyBuild(
  ctx: CommandContext,
  invocation: CommandInvocation,
) {
  const config = await getBuildConfig(ctx);
  const sandbox = await getSandbox(ctx);

  const build = Common.build(ctx, config, sandbox, {
    buildRoot: !invocation.options.flags.dependenciesOnly,
    buildDependencies: true,
  });

  let ejectingBuild = null;
  if (invocation.options.options.eject != null) {
    ejectingBuild = Common.ejectRootBuild(
      ctx,
      config,
      sandbox,
      invocation.options.options.eject,
    );
  }

  await Promise.all([ejectingBuild, build]);
}

export const options = {
  flags: ['--dependencies-only', '--silent'],
  options: ['--eject'],
};
