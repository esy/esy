/**
 * @flow
 */

require('babel-polyfill');

import type {Config, BuildSandbox, BuildTask, BuildPlatform} from '../types';
import type {Options as SandboxOptions} from '../build-sandbox';

import loudRejection from 'loud-rejection';
import userHome from 'user-home';
import * as path from 'path';
import chalk from 'chalk';

function getSandboxPath() {
  if (process.env.ESY__SANDBOX != null) {
    return process.env.ESY__SANDBOX;
  } else {
    // TODO: Need to change this to climb to closest package.json.
    return process.cwd();
  }
}

function getPrefixPath() {
  if (process.env.ESY__PREFIX != null) {
    return process.env.ESY__PREFIX;
  } else {
    return path.join(userHome, '.esy');
  }
}

function getReadOnlyStorePath() {
  if (process.env.ESY__READ_ONLY_STORE_PATH != null) {
    return process.env.ESY__READ_ONLY_STORE_PATH.split(':');
  } else {
    return [];
  }
}

function getBuildPlatform() {
  if (process.platform === 'darwin') {
    return 'darwin';
  } else if (process.platform === 'linux') {
    return 'linux';
  } else {
    // think cygwin/wsl
    return 'linux';
  }
}

export async function getBuildSandbox(
  ctx: CommandContext,
  options?: SandboxOptions,
): Promise<BuildSandbox> {
  const Sandbox = require('../build-sandbox');
  const sandbox = await Sandbox.fromDirectory(ctx.sandboxPath, options);
  if (sandbox.root.errors.length > 0) {
    sandbox.root.errors.forEach(error => {
      console.log(formatError(error.message));
    });
    process.exit(1);
  }
  return sandbox;
}

export async function getBuildConfig(ctx: CommandContext) {
  const {createForPrefix} = require('../config');

  return createForPrefix({
    prefixPath: ctx.prefixPath,
    sandboxPath: ctx.sandboxPath,
    buildPlatform: ctx.buildPlatform,
    readOnlyStorePath: ctx.readOnlyStorePath,
  });
}

function formatError(message: string, stack?: string) {
  let result = `${chalk.red('error:')} ${message}`;
  if (stack != null) {
    result += `\n${stack}`;
  }
  return result;
}

function error(error?: Error | string) {
  if (error != null) {
    const message = String(error.message ? error.message : error);
    const stack = error.stack ? String(error.stack) : undefined;
    console.log(formatError(message, stack));
  }
  process.exit(1);
}

export function indent(string: string, indent: string) {
  return string
    .split('\n')
    .map(line => indent + line)
    .join('\n');
}

export type CommandContext = {
  prefixPath: string,
  sandboxPath: string,
  readOnlyStorePath: Array<string>,
  buildPlatform: BuildPlatform,

  commandName: string,
  args: Array<string>,

  error(message?: string): any,
};

const commandsByName: {[name: string]: (CommandContext) => any} = {
  'build-eject': ctx => require('./esyBuildEject').default(ctx),
  build: ctx => require('./esyBuild').default(ctx),
  'build-shell': ctx => require('./esyBuildShell').default(ctx),
  release: ctx => require('./esyRelease').default(ctx),
  'import-opam': ctx => require('./esyImportOpam').default(ctx),
  'print-env': ctx => require('./esyPrintEnv').default(ctx),
  config: ctx => require('./esyConfig').default(ctx),
};

async function main() {
  const ctx: CommandContext = {
    prefixPath: getPrefixPath(),
    readOnlyStorePath: getReadOnlyStorePath(),
    sandboxPath: getSandboxPath(),
    buildPlatform: getBuildPlatform(),
    commandName: process.argv[2],
    args: process.argv.slice(3),
    error: error,
  };

  if (ctx.commandName == null) {
    ctx.error(`no command provided`);
  }

  const command = commandsByName[ctx.commandName];
  if (command != null) {
    await command(ctx);
  } else {
    ctx.error(`unknown command: ${ctx.commandName}`);
  }
}

main().catch(error);
loudRejection();
