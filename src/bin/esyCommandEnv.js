/**
 * @flow
 */

import type {CommandContext} from './esy';

import {getSandbox, getBuildConfig} from './esy';
import * as Task from '../build-task';
import * as Sandbox from '../sandbox';
import * as Env from '../environment';

export default async function esyCommandEnv(ctx: CommandContext) {
  const sandbox = await getSandbox(ctx);
  const config = await getBuildConfig(ctx);
  const env = Sandbox.getCommandEnv(sandbox, config);
  console.log(Env.printEnvironment(env));
}

export const noHeader = true;
