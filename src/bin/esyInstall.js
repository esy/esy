/**
 * @flow
 */

import {type CommandContext, runYarnCommand} from './esy';

export default async function esyInstall(ctx: CommandContext) {
  runYarnCommand();
}
