/**
 * @flow
 */

import type {CommandContext, CommandInvocation} from './esy';

import chalk from 'chalk';
import * as child from '@esy-ocaml/esy-install/src/util/child';
import * as path from '../lib/path';
import * as fs from '../lib/fs';
import commander from 'commander';
import parse from 'cli-argparse';
import runYarnCommand from './runYarnCommand';
import {Promise} from '../lib/Promise';

export default async function esyInit(
  ctx: CommandContext,
  invocation: CommandInvocation,
) {
  const clioptions = parse(invocation.args, {
    flags: ['--force'],
    options: ['--with'],
    strict: true,
  });

  const {['with']: packageName = 'create-esy-project'} = clioptions.options;
  const {force: forceInit = false} = clioptions.flags;

  const projectName = path.basename(ctx.sandboxPath);

  if (!forceInit) {
    const safePath = await isSafeToInitProjectIn(ctx.sandboxPath, projectName);
    if (!safePath) {
      process.exit(1);
    }
  }

  const globalFolder = path.join(ctx.prefixPath, 'install');

  const addInvocation = {
    commandName: 'global',
    args: ['add', packageName, '--global-folder', globalFolder],
    options: {options: {}, flags: {}},
  };

  await runYarnCommand(ctx, addInvocation, 'global');

  const binFolder = path.resolve(globalFolder, 'node_modules', '.bin');

  const commandName = packageName.replace(/^@[^\/]+\//, '');

  const command = path.resolve(binFolder, path.basename(commandName));
  const args = [projectName, ...clioptions.unparsed];

  try {
    await child.spawn(command, args, {
      cwd: path.resolve(ctx.sandboxPath, '..'),
      stdio: `inherit`,
      shell: true,
    });
  } catch (err) {
    process.exit(1);
  }
}

export const noParse = true;

async function isSafeToInitProjectIn(path, name) {
  const validFiles = [
    '.DS_Store',
    'Thumbs.db',
    '.git',
    '.gitignore',
    '.idea',
    'README.md',
    'LICENSE',
    '.hg',
    '.hgignore',
    '.hgcheck',
  ];

  const files = await fs.readdir(path);

  const conflicts = await Promise.all(
    files.filter(file => {
      if (validFiles.includes(file)) {
        return Promise.resolve(true);
      }

      return fs.lstat(file).then(stats => !stats.isFile());
    }),
  );

  if (conflicts.length < 1) {
    return true;
  }

  console.log();
  console.log(`Your directory ${chalk.green(name)} is not empty.`);
  console.log(`Pass ${chalk.cyan('--force')} to override this check.`);
  console.log();

  return false;
}
