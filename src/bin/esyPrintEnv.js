/**
 * @flow
 */

import type {CommandContext} from './esy';

import {getSandbox, getBuildConfig} from './esy';
import * as Task from '../build-task';
import * as Sandbox from '../sandbox';
import * as Env from '../environment';

export default async function esyPrintEnv(ctx: CommandContext) {
  // TODO: It's just a status command. Print the command that would be
  // used to setup the environment along with status of
  // the build processes, staleness, package validity etc.
  const sandbox = await getSandbox(ctx);
  const config = await getBuildConfig(ctx);
  const env = Sandbox.getCommandEnv(sandbox, config);
  console.log(Env.printEnvironmentMap(env));
}
