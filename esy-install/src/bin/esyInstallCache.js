/**
 * @flow
 */

import type {CommandContext, CommandInvocation} from './esy';
import runYarnCommand from './runYarnCommand';

export default async function esyInstallCache(
  ctx: CommandContext,
  invocation: CommandInvocation,
) {
  await runYarnCommand(ctx, invocation, 'cache');
}
