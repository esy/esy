/**
 * @flow
 */

import type {CommandContext, CommandInvocation} from './esy';
import runYarnCommand from './runYarnCommand';

export default async function esyInstall(
  ctx: CommandContext,
  invocation: CommandInvocation,
) {
  await runYarnCommand(ctx, invocation, 'install');
}
