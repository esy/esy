/**
 * @flow
 */

import type {CommandContext, CommandInvocation} from './esy';

import chalk from 'chalk';
import * as child from '@esy-ocaml/esy-install/src/util/child';
import * as path from 'path';
import * as fs from 'fs';
import commander from 'commander';
import parse from 'cli-argparse';
import runYarnCommand from './runYarnCommand';

export default async function esyCreate(
  ctx: CommandContext,
  invocation: CommandInvocation,
) {
  const {unparsed} = parse(invocation.args);
  let builderName;
  let builderArgs;

  if (unparsed.length) {
    [builderName, ...builderArgs] = invocation.args;
  } else {
    builderName = 'esy-project';
    builderArgs = invocation.args;
  }

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

  await child.spawn(command, [...builderArgs], {stdio: `inherit`, shell: true});
}

export const noParse = true;
