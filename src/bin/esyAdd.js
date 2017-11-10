/**
 * @flow
 */

import type {CommandContext, CommandInvocation} from './esy';

import * as path from 'path';
import runYarnCommand from './runYarnCommand.js';
import esyBuild from './esyBuild.js';

export default async function esyAdd(ctx: CommandContext, invocation: CommandInvocation) {
  await runYarnCommand(ctx, invocation, 'add');
}
