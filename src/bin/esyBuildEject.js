/**
 * @flow
 */

import type {CommandContext, CommandInvocation} from './esy';
import type {BuildPlatform} from '../types';

import * as path from 'path';
import invariant from 'invariant';
import outdent from 'outdent';

import {getSandbox} from './esy';
import * as BuildEject from '../build-eject.js';

export default async function buildEjectCommand(
  ctx: CommandContext,
  invocation: CommandInvocation,
) {
  const [_buildEjectPath, buildPlatformArg] = invocation.args;
  const buildPlatform: BuildPlatform = determineBuildPlatformFromArgument(
    ctx,
    buildPlatformArg,
    ctx.buildPlatform,
  );
  const sandbox = await getSandbox(ctx, {forRelease: true});
  await BuildEject.eject(
    sandbox,
    path.join(ctx.sandboxPath, 'node_modules', '.cache', '_esy', 'build-eject'),
    {buildPlatform, reporter: ctx.reporter},
  );
}

/**
 * This is temporary, mostly here for testing. Soon, esy will automatically
 * create build ejects for all valid platforms.
 */
function determineBuildPlatformFromArgument(
  ctx,
  arg,
  defaultBuildPlatform,
): BuildPlatform {
  if (arg === '' || arg === null || arg === undefined) {
    return defaultBuildPlatform;
  } else {
    if (arg === 'darwin') {
      return 'darwin';
    } else if (arg === 'linux') {
      return 'linux';
    } else if (arg === 'cygwin') {
      return 'cygwin';
    }
    ctx.error(outdent`
      Specified build platform ${arg} is invalid: Pass one of "linux", "cygwin", or "darwin".
    `);
    invariant(false, 'Impossible to reach, just to make flow happy');
  }
}
