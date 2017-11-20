/**
 * @flow
 */

import * as path from 'path';
import * as fs from 'fs';
import invariant from 'invariant';
import commander from 'commander';
import lockfile from 'proper-lockfile';
import {
  ConsoleReporter,
  JSONReporter,
} from '@esy-ocaml/esy-install/src/reporters/index.js';
import commands from '@esy-ocaml/esy-install/src/cli/commands/index.js';
import {registries, registryNames} from '@esy-ocaml/esy-install/src/registries/index.js';
import {MessageError} from '@esy-ocaml/esy-install/src/errors.js';
import * as network from '@esy-ocaml/esy-install/src/util/network.js';
import onDeath from 'death';
import * as constants from '@esy-ocaml/esy-install/src/constants.js';
import Config from '@esy-ocaml/esy-install/src/config.js';
import {getRcConfigForCwd, getRcArgs} from '@esy-ocaml/esy-install/src/rc.js';
import type {CommandContext, CommandInvocation} from './esy';

export default function runYarnCommand(
  ctx: CommandContext,
  invocation: CommandInvocation,
  commandName: string,
): Promise<void> {
  const cacheFolder = path.join(ctx.prefixPath, 'install-cache');
  return main(ctx, invocation, {commandName, cacheFolder});
}

async function main(
  ctx: CommandContext,
  invocation: CommandInvocation,
  {
    commandName,
    cacheFolder,
  }: {
    commandName: string,
    cacheFolder: string,
  },
): Promise<void> {
  // TODO:
  // handleSignals();

  const boolify = val => val.toString().toLowerCase() !== 'false' && val !== '0';

  // set global options
  commander.version(ctx.version, '-v, --version');
  commander.usage('[command] [flags]');
  commander.option('--verbose', 'output verbose messages on internal operations');
  commander.option(
    '--offline',
    'trigger an error if any required dependencies are not available in local cache',
  );
  commander.option(
    '--prefer-offline',
    'use network only if dependencies are not available in local cache',
  );
  commander.option('--strict-semver');
  commander.option('--json', '');
  commander.option('--ignore-scripts', "don't run lifecycle scripts");
  commander.option('--har', 'save HAR output of network traffic');
  commander.option('--ignore-platform', 'ignore platform checks');
  commander.option('--ignore-engines', 'ignore engines check');
  commander.option('--ignore-optional', 'ignore optional dependencies');
  commander.option(
    '--force',
    'install and build packages even if they were built before, overwrite lockfile',
  );
  commander.option(
    '--skip-integrity-check',
    'run install without checking if node_modules is installed',
  );
  commander.option(
    '--check-files',
    'install will verify file tree of packages for consistency',
  );
  commander.option('--no-bin-links', "don't generate bin links when setting up packages");
  commander.option('--flat', 'only allow one version of a package');
  commander.option('--prod, --production [prod]', '', boolify);
  commander.option('--no-lockfile', "don't read or generate a lockfile");
  commander.option('--pure-lockfile', "don't generate a lockfile");
  commander.option(
    '--frozen-lockfile',
    "don't generate a lockfile and fail if an update is needed",
  );
  commander.option(
    '--link-duplicates',
    'create hardlinks to the repeated modules in node_modules',
  );
  commander.option(
    '--link-folder <path>',
    'specify a custom folder to store global links',
  );
  commander.option(
    '--global-folder <path>',
    'specify a custom folder to store global packages',
  );
  commander.option(
    '--modules-folder <path>',
    'rather than installing modules into the node_modules folder relative to the cwd, output them here',
  );
  commander.option(
    '--preferred-cache-folder <path>',
    'specify a custom folder to store the yarn cache if possible',
  );
  commander.option(
    '--cache-folder <path>',
    'specify a custom folder that must be used to store the yarn cache',
  );
  commander.option(
    '--mutex <type>[:specifier]',
    'use a mutex to ensure only one yarn instance is executing',
  );
  commander.option(
    '--emoji [bool]',
    'enable emoji in output',
    boolify,
    process.platform === 'darwin',
  );
  commander.option(
    '-s, --silent',
    'skip Yarn console logs, other types of logs (script output) will be printed',
  );
  commander.option('--cwd <cwd>', 'working directory to use', process.cwd());
  commander.option('--proxy <host>', '');
  commander.option('--https-proxy <host>', '');
  commander.option('--registry <url>', 'override configuration registry');
  commander.option('--no-progress', 'disable progress bar');
  commander.option(
    '--network-concurrency <number>',
    'maximum number of concurrent network requests',
    parseInt,
  );
  commander.option(
    '--network-timeout <milliseconds>',
    'TCP timeout for network requests',
    parseInt,
  );
  commander.option('--non-interactive', 'do not show interactive prompts');
  commander.option(
    '--scripts-prepend-node-path [bool]',
    'prepend the node executable dir to the PATH in scripts',
    boolify,
  );
  commander.option(
    '--no-node-version-check',
    'do not warn when using a potentially unsupported Node version',
  );

  let isKnownCommand = Object.prototype.hasOwnProperty.call(commands, commandName);

  const command = commands[commandName];

  command.setFlags(commander);
  commander.parse([
    'esy',
    commandName,
    ...getRcArgs(commandName, invocation.args),
    ...invocation.args,
  ]);

  const exit = exitCode => {
    process.exitCode = exitCode || 0;
    ctx.reporter.close();
  };

  ctx.reporter.initPeakMemoryCounter();

  const config = new Config(ctx.reporter);
  const outputWrapper = !commander.json && command.hasWrapper(commander, commander.args);

  if (command.noArguments && commander.args.length) {
    ctx.reporter.error(ctx.reporter.lang('noArguments'));
    ctx.reporter.info(command.getDocsInfo);
    exit(1);
    return;
  }

  //
  if (commander.yes) {
    ctx.reporter.warn(ctx.reporter.lang('yesWarning'));
  }

  //
  if (!commander.offline && network.isOffline()) {
    ctx.reporter.warn(ctx.reporter.lang('networkWarning'));
  }

  //
  const run = (): Promise<void> => {
    invariant(command, 'missing command');

    return command.run(config, ctx.reporter, commander, commander.args).then(exitCode => {
      if (outputWrapper) {
        ctx.reporter.footer(false);
      }
      return exitCode;
    });
  };

  //
  const runEventuallyWithFile = (
    mutexFilename: ?string,
    isFirstTime?: boolean,
  ): Promise<void> => {
    return new Promise(resolve => {
      const lockFilename =
        mutexFilename || path.join(config.cwd, constants.SINGLE_INSTANCE_FILENAME);
      lockfile.lock(
        lockFilename,
        {realpath: false},
        (err: mixed, release: () => void) => {
          if (err) {
            if (isFirstTime) {
              ctx.reporter.warn(ctx.reporter.lang('waitingInstance'));
            }
            setTimeout(() => {
              resolve(runEventuallyWithFile(mutexFilename, false));
            }, 200); // do not starve the CPU
          } else {
            onDeath(() => {
              process.exitCode = 1;
            });
            resolve(run().then(release));
          }
        },
      );
    });
  };

  function onUnexpectedError(err: Error) {
    function indent(str: string): string {
      return (
        '\n  ' +
        str
          .trim()
          .split('\n')
          .join('\n  ')
      );
    }

    const log = [];
    log.push(`Arguments: ${indent(process.argv.join(' '))}`);
    log.push(`PATH: ${indent(process.env.PATH || 'undefined')}`);
    log.push(`Yarn version: ${indent(ctx.version)}`);
    log.push(`Node version: ${indent(process.versions.node)}`);
    log.push(`Platform: ${indent(process.platform + ' ' + process.arch)}`);

    // add manifests
    for (const registryName of registryNames) {
      for (const filename of registries[registryName].filenameList) {
        const possibleLoc = path.join(config.cwd, filename);
        const manifest = fs.existsSync(possibleLoc)
          ? fs.readFileSync(possibleLoc, 'utf8')
          : 'No manifest';
        log.push(`${registryName} manifest (${filename}): ${indent(manifest)}`);
      }
    }

    // lockfile
    const lockLoc = path.join(
      config.lockfileFolder || config.cwd, // lockfileFolder might not be set at this point
      constants.LOCKFILE_FILENAME,
    );
    const lockfile = fs.existsSync(lockLoc)
      ? fs.readFileSync(lockLoc, 'utf8')
      : 'No lockfile';
    log.push(`Lockfile: ${indent(lockfile)}`);

    log.push(`Trace: ${indent(err.stack)}`);

    const errorReportLoc = writeErrorReport(log);

    ctx.reporter.error(ctx.reporter.lang('unexpectedError', err.message));

    if (errorReportLoc) {
      ctx.reporter.info(ctx.reporter.lang('bugReport', errorReportLoc));
    }
  }

  function writeErrorReport(log): ?string {
    const errorReportLoc = config.enableMetaFolder
      ? path.join(config.cwd, constants.META_FOLDER, 'yarn-error.log')
      : path.join(config.cwd, 'yarn-error.log');

    try {
      fs.writeFileSync(errorReportLoc, log.join('\n\n') + '\n');
    } catch (err) {
      ctx.reporter.error(
        ctx.reporter.lang('fileWriteError', errorReportLoc, err.message),
      );
      return undefined;
    }

    return errorReportLoc;
  }

  const cwd = command.shouldRunInCurrentCwd
    ? commander.cwd
    : findProjectRoot(commander.cwd);

  return config
    .init({
      cwd,
      commandName,

      binLinks: commander.binLinks,
      modulesFolder: commander.modulesFolder,
      linkFolder: commander.linkFolder,
      globalFolder: commander.globalFolder,
      preferredCacheFolder: commander.preferredCacheFolder,
      cacheFolder: cacheFolder,
      preferOffline: commander.preferOffline,
      captureHar: commander.har,
      ignorePlatform: commander.ignorePlatform,
      ignoreEngines: commander.ignoreEngines,
      ignoreScripts: commander.ignoreScripts,
      offline: commander.preferOffline || commander.offline,
      looseSemver: !commander.strictSemver,
      production: commander.production,
      httpProxy: commander.proxy,
      httpsProxy: commander.httpsProxy,
      registry: commander.registry,
      networkConcurrency: commander.networkConcurrency,
      networkTimeout: commander.networkTimeout,
      nonInteractive: commander.nonInteractive,
      scriptsPrependNodePath: commander.scriptsPrependNodePath,
    })
    .then(() => {
      // lockfile check must happen after config.init sets lockfileFolder
      if (
        command.requireLockfile &&
        !fs.existsSync(path.join(config.lockfileFolder, constants.LOCKFILE_FILENAME))
      ) {
        throw new MessageError(ctx.reporter.lang('noRequiredLockfile'));
      }

      // option "no-progress" stored in yarn config
      const noProgressConfig = config.registries.yarn.getOption('no-progress');

      if (noProgressConfig) {
        ctx.reporter.disableProgress();
      }

      // verbose logs outputs process.uptime() with this line we can sync uptime to absolute time on the computer
      ctx.reporter.verbose(`current time: ${new Date().toISOString()}`);

      const mutex: mixed = commander.mutex;
      if (mutex && typeof mutex === 'string') {
        const separatorLoc = mutex.indexOf(':');
        let mutexType;
        let mutexSpecifier;
        if (separatorLoc === -1) {
          mutexType = mutex;
          mutexSpecifier = undefined;
        } else {
          mutexType = mutex.substring(0, separatorLoc);
          mutexSpecifier = mutex.substring(separatorLoc + 1);
        }

        if (mutexType === 'file') {
          return runEventuallyWithFile(mutexSpecifier, true).then(exit);
        } else {
          throw new MessageError(`Unknown single instance type ${mutexType}`);
        }
      } else {
        return run().then(exit);
      }
    })
    .catch((err: Error) => {
      ctx.reporter.verbose(err.stack);

      if (err.constructor && err.constructor.name === 'MessageError') {
        ctx.reporter.error(err.message);
      } else {
        onUnexpectedError(err);
      }

      if (command.getDocsInfo) {
        ctx.reporter.info(command.getDocsInfo);
      }

      return exit(1);
    });
}

function findProjectRoot(base: string): string {
  let prev = null;
  let dir = base;

  do {
    for (const filename of constants.PROJECT_ROOT_MARKER) {
      if (fs.existsSync(path.join(dir, filename))) {
        return dir;
      }
    }

    prev = dir;
    dir = path.dirname(dir);
  } while (dir !== prev);

  return base;
}
