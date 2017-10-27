/**
 * @flow
 */

require('babel-polyfill');

import type {BuildConfig, BuildSandbox, BuildTask, BuildPlatform} from '../types';
import type {Options as SandboxOptions} from '../build-sandbox';

import loudRejection from 'loud-rejection';
import userHome from 'user-home';
import * as path from 'path';
import chalk from 'chalk';

import * as Config from '../build-config';

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
  sandboxPath: string,
  options?: SandboxOptions,
): Promise<BuildSandbox> {
  const Sandbox = require('../build-sandbox');
  const sandbox = await Sandbox.fromDirectory(sandboxPath, options);
  if (sandbox.root.errors.length > 0) {
    sandbox.root.errors.forEach(error => {
      console.log(formatError(error.message));
    });
    process.exit(1);
  }
  return sandbox;
}

function formatError(message: string, stack?: string) {
  let result = `${chalk.red('error:')} ${message}`;
  if (stack != null) {
    result += `\n${stack}`;
  }
  return result;
}

function error(error: Error | string) {
  const message = String(error.message ? error.message : error);
  const stack = error.stack ? String(error.stack) : undefined;
  console.log(formatError(message, stack));
  process.exit(1);
}

export function indent(string: string, indent: string) {
  return string.split('\n').map(line => indent + line).join('\n');
}

export type CommandContext = {
  config: BuildConfig,
  commandName: string,
  args: Array<string>,
  error(message: string): void,
};

const commandsByName: {[name: string]: (CommandContext) => any} = {
  'build-eject': ctx => require('./esyBuildEject').default(ctx),
  build: ctx => require('./esyBuild').default(ctx),
  release: ctx => require('./esyRelease').default(ctx),
  'import-opam': ctx => require('./esyImportOpam').default(ctx),
  'print-env': ctx => require('./esyPrintEnv').default(ctx),
  config: ctx => require('./esyConfig').default(ctx),
};

async function main() {
  const ctx: CommandContext = {
    config: Config.createForPrefix({
      prefixPath: getPrefixPath(),
      sandboxPath: getSandboxPath(),
      buildPlatform: getBuildPlatform(),
    }),
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
