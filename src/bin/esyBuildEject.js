/**
 * @flow
 */

import type {CommandContext, CommandInvocation} from './esy';
import type {BuildPlatform} from '../types';

import * as path from 'path';
import invariant from 'invariant';
import outdent from 'outdent';

import {getSandbox} from './esy';
import * as Config from '../config';
import * as MakefileBuilder from '../builders/makefile-builder';

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
  const buildConfig = createConfig(buildPlatform);
  MakefileBuilder.eject(
    sandbox,
    path.join(ctx.sandboxPath, 'node_modules', '.cache', '_esy', 'build-eject'),
    buildConfig,
  );
}

/**
 * Note that Makefile based builds defers exact locations of sandbox and store
 * to some later point because ejected builds can be transfered to other
 * machines.
 *
 * That means that build env is generated in a way which can be configured later
 * with `$ESY_EJECT__SANDBOX` and `$ESY_EJECT__STORE` environment variables.
 */
function createConfig(buildPlatform: BuildPlatform) {
  const STORE_PATH = '$ESY_EJECT__STORE';
  const SANDBOX_PATH = '$ESY_EJECT__SANDBOX';
  const buildConfig = Config.create({
    storePath: STORE_PATH,
    sandboxPath: SANDBOX_PATH,
    buildPlatform,
    readOnlyStorePath: [],
  });
  return buildConfig;
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
