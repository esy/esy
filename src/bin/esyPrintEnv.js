/**
 * @flow
 */

import type {CommandContext} from './esy';

import {getBuildSandbox, getBuildConfig} from './esy';
import * as Task from '../build-task';
import * as Sandbox from '../sandbox';
import * as Env from '../environment';

export default async function esyPrintEnv(ctx: CommandContext) {
  // TODO: It's just a status command. Print the command that would be
  // used to setup the environment along with status of
  // the build processes, staleness, package validity etc.
  const sandbox = await getBuildSandbox(ctx);
  const config = await getBuildConfig(ctx);
  const task = Task.fromBuildSandbox(sandbox, config);
  const env = Sandbox.getCommandEnv(task, config);
  console.log(Env.printEnvironment(task.env));
}
