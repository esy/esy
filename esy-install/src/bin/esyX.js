/**
 * @flow
 */

import type {CommandContext, CommandInvocation} from './esy';

import {getSandbox, getBuildConfig} from './esy';
import * as Task from '../build-task';
import * as Sandbox from '../sandbox';
import * as Env from '../environment';

export default async function esyX(ctx: CommandContext, invocation: CommandInvocation) {
  const sandbox = await getSandbox(ctx);
}
