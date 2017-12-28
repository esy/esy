/**
 * @flow
 */

import * as path from 'path';
import * as fs from 'fs';
import type {CommandContext, CommandInvocation} from './esy';
import runYarnCommand from './runYarnCommand';
import * as child from '@esy-ocaml/esy-install/src/util/child';

export default async function esyCreate(
  ctx: CommandContext,
  invocation: CommandInvocation,
) {
  const [builderName = 'esy-project', ...rest] = invocation.args;

  const packageName = builderName.replace(/^(@[^\/]+\/)?/, '$1create-');
  const commandName = packageName.replace(/^@[^\/]+\//, '');

  const globalFolder = path.join(ctx.prefixPath, 'install');

  const addInvocation = {
    commandName: 'global',
    args: ['add', packageName, '--global-folder', globalFolder],
    options: {options: {}, flags: {}},
  };

  await runYarnCommand(ctx, addInvocation, 'global');

  const binFolder = path.resolve(globalFolder, 'node_modules', '.bin');
  const command = path.resolve(binFolder, path.basename(commandName));

  await child.spawn(command, [...rest], {stdio: `inherit`, shell: true});
}

export const noParse = true;
