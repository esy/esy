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

export default async function esyCreate(
  ctx: CommandContext,
  invocation: CommandInvocation,
) {
  const clioptions = parse(invocation.args);

  const {['with']: packageName = 'create-esy-project', ...options} = clioptions.options;
  const {force: forceInit = false} = clioptions.flags;

  const projectName = path.basename(ctx.sandboxPath);
  const commandName = packageName.replace(/^@[^\/]+\//, '');

  if (!forceInit) {
    const safePath = await isSafeToInitProjectIn(ctx.sandboxPath, projectName);
    if (!safePath) {
      return;
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
  const command = path.resolve(binFolder, path.basename(commandName));

  try {
    await child.spawn(command, [projectName], {
      cwd: path.resolve(ctx.sandboxPath, '..'),
      stdio: `inherit`,
      shell: true,
    });
  } catch (err) {
    return;
  }
}

// export const noHeader = true;
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
    'web.iml',
    '.hg',
    '.hgignore',
    '.hgcheck',
  ];
  console.log();

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

  console.log(`Your directory ${chalk.green(name)} contains files that could conflict:`);
  console.log();
  for (const file of conflicts) {
    console.log(`  ${file}`);
  }
  console.log();
  console.log('Either try using an empty directory, or remove the files listed above.');
  console.log(`Alternatively, pass ${chalk.cyan('--force')} to override this check.`);

  return false;
}
