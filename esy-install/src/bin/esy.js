/**
 * @flow
 */

require('babel-polyfill');

import type {Config, Reporter, Sandbox, BuildTask, BuildPlatform} from '../types';
import type {Options as SandboxOptions} from '../sandbox/project-sandbox';

import loudRejection from 'loud-rejection';
import userHome from 'user-home';
import * as path from '../lib/path';
import chalk from 'chalk';
import outdent from 'outdent';
import parse from 'cli-argparse';
import * as rc from '../rc.js';
import {SandboxError} from '../errors.js';
import {ConsoleReporter, HighSeverityReporter} from '../reporter.js';

const pkg = require('../../package.json');
// for deterministic test output
if (process.env.NODE_ENV === 'test') {
  pkg.version = '0.0.0';
}

const cwd = process.cwd();
const rcConfig = rc.getRcConfigForCwd(cwd);

function getSandboxPath() {
  if (process.env.ESY__SANDBOX != null) {
    return process.env.ESY__SANDBOX;
  } else {
    // TODO: Need to change this to climb to closest package.json.
    return cwd;
  }
}

function getPrefixPath() {
  if (process.env.ESY__PREFIX != null) {
    return process.env.ESY__PREFIX;
  } else if (rcConfig['esy-prefix-path'] != null) {
    return rcConfig['esy-prefix-path'];
  } else {
    return path.join(userHome, '.esy');
  }
}

function getImportPaths() {
  if (process.env.ESY__IMPORT_PATH != null) {
    return process.env.ESY__IMPORT_PATH.split(':');
  } else {
    return rcConfig['esy-import-path'];
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
  options?: {forRelease?: boolean} = {},
): Promise<Sandbox> {
  const {forRelease = false} = options;
  const S = require('../sandbox/project-sandbox');
  const sandbox = await S.create(ctx.sandboxPath, {
    installCachePath: path.join(ctx.prefixPath, 'install-cache'),
    reporter: ctx.reporter,
    forRelease,
  });
  return sandbox;
}

export async function getBuildConfig(
  ctx: CommandContext,
): Promise<Config<path.AbsolutePath>> {
  const {createForPrefix} = require('../config');

  return createForPrefix({
    reporter: ctx.reporter,
    prefixPath: ctx.prefixPath,
    sandboxPath: ctx.sandboxPath,
    buildPlatform: ctx.buildPlatform,
    importPaths: ctx.importPaths,
  });
}

function formatError(message: string, stack?: string) {
  let result = message;
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
  importPaths: Array<string>,
  buildPlatform: BuildPlatform,
  executeCommand: (commandName: string, args: string[]) => Promise<void>,
  version: string,
  reporter: Reporter,
  error(message?: string): any,
};

export type CommandInvocation = {
  commandName: string,
  args: Array<string>,
  options: {
    options: {[name: string]: string},
    flags: {[name: string]: boolean},
  },
};

type Command = {
  default: (CommandContext, CommandInvocation) => any,
  options?: Object,
  noHeader?: boolean,
  noParse?: boolean,
};

const commandsByName: {[name: string]: () => Command} = {
  init: () => require('./esyInit'),
  release: () => require('./esyRelease'),
  config: () => require('./esyConfig'),
  install: () => require('./esyInstall'),
  add: () => require('./esyAdd'),
  'build-plan': () => require('./esyBuildPlan'),
  'import-opam': () => require('./esyImportOpam'),
  'command-env': () => require('./esyCommandEnv'),
  'sandbox-env': () => require('./esySandboxEnv'),
  'build-env': () => require('./esyBuildEnv'),
  'install-cache': () => require('./esyInstallCache'),
  'export-dependencies': () => require('./esyExportDependencies'),
  'import-dependencies': () => require('./esyImportDependencies'),
};

const options = {
  flags: ['--silent', '--verbose'],
};

async function main() {
  let commandName = null;
  const opts = [];
  const args = [];

  // We consiume all options which go before the command (if any), then we
  // collect all remainings into `args` which then willbe processed by command
  // specific argument parser.
  for (let arg of process.argv.slice(2)) {
    arg = arg.trim();
    if (arg === '') {
      continue;
    }
    if (commandName == null) {
      if (arg.startsWith('-')) {
        opts.push(arg);
      } else {
        commandName = arg;
      }
    } else {
      args.push(arg);
    }
  }

  const {flags} = parse(opts, options);

  const isTTY = (process.stdout: any).isTTY;

  const consoleReporter = new ConsoleReporter({
    emoji: false,
    verbose: flags.verbose,
    noProgress: !isTTY || (process.env.DEBUG != null && process.env.DEBUG !== ''),
    isSilent: process.env.ESY__SILENT === '1',
  });

  const highSeverityReporter = new HighSeverityReporter(consoleReporter);

  const reporter = !flags.silent ? consoleReporter : highSeverityReporter;

  const error = (error?: Error | string) => {
    if (error != null) {
      const message = String(error.message ? error.message : error);
      const stack = error.stack ? String(error.stack) : undefined;
      reporter.error(formatError(message, stack));
    }
    reporter.close();
    process.exit(1);
  };

  if (commandName == null) {
    error('no command provided');
  }

  if (commandName != null && commandsByName[commandName] != null) {
    const command = commandsByName[commandName];

    const executeCommand = async (commandName, initialArgs) => {
      const command = commandsByName[commandName];
      const commandImpl = command();
      let args = [];
      let options = {options: {}, flags: {}};
      if (commandImpl.noParse) {
        args = initialArgs;
      } else {
        options = parse(initialArgs, {
          ...commandImpl.options,
          strict: true,
        });
        for (const opt of options.unparsed) {
          if (opt.startsWith('-')) {
            error(`unknown option ${opt}`);
          }
          args.push(opt);
        }
      }
      await commandImpl.default(ctx, {commandName, args, options});
    };

    const ctx: CommandContext = {
      version: pkg.version,
      prefixPath: getPrefixPath(),
      importPaths: getImportPaths(),
      sandboxPath: getSandboxPath(),
      buildPlatform: getBuildPlatform(),
      executeCommand,
      error,
      reporter,
    };

    try {
      await executeCommand(commandName, args);
    } catch (error) {
      if (error instanceof SandboxError) {
        for (const err of error.errors) {
          if (err.origin != null) {
            ctx.reporter.error(outdent`
              ${err.origin.packagePath}: ${err.reason}
            `);
          } else {
            ctx.reporter.error(err.reason);
          }
        }
        process.exit(1);
      } else {
        throw error;
      }
    }
  } else if (commandName != null) {
    error(`unknown command: ${commandName}`);
  }
}

main().catch(error);
loudRejection();
