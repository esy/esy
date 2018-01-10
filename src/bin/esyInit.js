/**
 * @flow
 */

import type {CommandContext, CommandInvocation} from './esy';

import chalk from 'chalk';
import * as child from '@esy-ocaml/esy-install/src/util/child';
import * as path from '../lib/path';
import * as fs from '../lib/fs';
import commander from 'commander';
import dashify from 'dashify';
import parse from 'cli-argparse';
import runYarnCommand from './runYarnCommand';
import {Promise} from '../lib/Promise';

export default async function esyInit(
  ctx: CommandContext,
  invocation: CommandInvocation,
) {
  const clioptions = parse(invocation.args);

  const {['with']: packageName = 'create-esy-project', ...options} = clioptions.options;
  const {force: forceInit = false, ...flags} = clioptions.flags;

  const projectName = path.basename(ctx.sandboxPath);

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

  const commandName = packageName.replace(/^@[^\/]+\//, '');

  const command = path.resolve(binFolder, path.basename(commandName));
  const args = [
    projectName,
    ...clioptions.unparsed,
    ...argvify(options),
    ...argvify(flags),
  ];

  try {
    await child.spawn(command, args, {
      cwd: path.resolve(ctx.sandboxPath, '..'),
      stdio: `inherit`,
      shell: true,
    });
  } catch (err) {
    return;
  }
}

export const noParse = true;

function argvify(options: {[name: string]: any}) {
  const argv = [];

  for (const key in options) {
    const opt = options[key];

    const dashed = dashify(key);

    if (opt === true) {
      argv.push(`--${dashed}`);
    } else if (typeof opt === 'number') {
      const flag = new Array(opt + 1).join(key);
      argv.push(`-${flag}`);
    } else {
      argv.push(`--${dashed}`, opt);
    }
  }
  return argv;
}

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
