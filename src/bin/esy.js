/**
 * @flow
 */

require('babel-polyfill');

import type {Config, Sandbox, BuildTask, BuildPlatform} from '../types';
import type {Options as SandboxOptions} from '../build-sandbox';

import loudRejection from 'loud-rejection';
import userHome from 'user-home';
import * as path from '../lib/path';
import chalk from 'chalk';
import parse from 'cli-argparse';

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

export async function getSandbox(
  ctx: CommandContext,
  options?: SandboxOptions,
): Promise<Sandbox> {
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

export async function getBuildConfig(
  ctx: CommandContext,
): Promise<Config<path.AbsolutePath>> {
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

export function runYarnCommand() {
  const doubleDashIndex = process.argv.findIndex(element => element === '--');
  const startArgs = process.argv.slice(0, 2);
  const args = process.argv.slice(
    2,
    doubleDashIndex === -1 ? process.argv.length : doubleDashIndex,
  );
  const endArgs = doubleDashIndex === -1 ? [] : process.argv.slice(doubleDashIndex);

  const installCacheFolder = path.join(getPrefixPath(), 'install-cache');
  args.unshift('--cache-folder', installCacheFolder);

  const EsyInstall = require('@esy-ocaml/esy-install/src/cli/index');
  EsyInstall.main({startArgs, args, endArgs});
}

export type CommandContext = {
  prefixPath: string,
  sandboxPath: string,
  readOnlyStorePath: Array<string>,
  buildPlatform: BuildPlatform,

  commandName: string,
  args: Array<string>,
  options: {
    options: {[name: string]: string},
    flags: {[name: string]: boolean},
  },

  error(message?: string): any,
};

type Command = {
  default: CommandContext => any,
  options?: Object,
};

const commandsByName: {[name: string]: () => Command} = {
  build: () => require('./esyBuild'),
  release: () => require('./esyRelease'),
  config: () => require('./esyConfig'),
  install: () => require('./esyInstall'),
  add: () => require('./esyAdd'),
  'build-eject': () => require('./esyBuildEject'),
  'build-shell': () => require('./esyBuildShell'),
  'import-opam': () => require('./esyImportOpam'),
  'print-env': () => require('./esyPrintEnv'),
  'install-cache': () => require('./esyInstallCache'),
};

async function main() {
  const commandName = process.argv[2];

  if (commandName == null) {
    error(`no command provided`);
  }

  const command = commandsByName[commandName];
  if (command != null) {
    const commandImpl = command();
    const options = parse(process.argv.slice(3), {...commandImpl.options, strict: true});
    const args = [];
    for (const opt of options.unparsed) {
      if (opt.startsWith('-')) {
        error(`unknown option ${opt}`);
      }
      args.push(opt);
    }
    const commandCtx: CommandContext = {
      prefixPath: getPrefixPath(),
      readOnlyStorePath: getReadOnlyStorePath(),
      sandboxPath: getSandboxPath(),
      buildPlatform: getBuildPlatform(),
      commandName,
      args,
      options,
      error: error,
    };
    await commandImpl.default(commandCtx);
  } else {
    error(`unknown command: ${commandName}`);
  }
}

main().catch(error);
loudRejection();
