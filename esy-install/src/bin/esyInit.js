/**
 * @flow
 */

import type {CommandContext, CommandInvocation} from './esy';

import chalk from 'chalk';
import * as child from '../lib/child_process';
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
  const program = new commander.Command();
  let initPath;

  program
    .usage('[options] [<path>]')
    .option('-y, --yes', 'answer yes to all interactive prompts or use defaults')
    .option('--with <template>', 'use custom starter template', 'create-esy-project')
    .option('--force', 'bypass init path sanity check')
    .allowUnknownOption(true)
    .arguments('[<path>]')
    .action(function(path) {
      initPath = path;
    });

  program.parse(['esy', 'init', ...invocation.args]);

  const projectPath = initPath ? path.resolve(initPath) : ctx.sandboxPath;
  const projectName = path.basename(projectPath);

  if (!program.force) {
    // Perform sanity check for project path
    if (await fs.exists(projectPath)) {
      const safePath = await isSafeToInitProjectIn(projectPath, projectName);
      if (!safePath) {
        process.exit(1);
      }
    }
  }

  // Cache template package in our designated folder
  const templatePackage = program.with;
  const globalFolder = path.join(ctx.prefixPath, 'install');

  const addInvocation = {
    commandName: 'global',
    args: ['add', templatePackage, '--global-folder', globalFolder],
    options: {options: {}, flags: {}},
  };

  await runYarnCommand(ctx, addInvocation, 'global');

  // Strip cli arguments before passing them to template script
  const clioptions = parse(initPath ? invocation.args.slice(0, -1) : invocation.args, {
    flags: ['--force'],
    options: ['--with'],
    strict: true,
  });

  const args = [projectName, ...clioptions.unparsed];

  // Make sure template CWD exists
  const commandCwd = path.resolve(projectPath, '..');
  await fs.mkdirp(commandCwd);

  // Run template script
  const binFolder = path.resolve(globalFolder, 'node_modules', '.bin');

  const commandName = templatePackage.replace(/^@[^\/]+\//, '');
  const command = path.resolve(binFolder, path.basename(commandName));

  try {
    await child.spawn(command, args, {
      cwd: commandCwd,
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
