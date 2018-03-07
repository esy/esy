/**
 * @flow
 */

import type {CommandContext, CommandInvocation} from './esy';
import * as types from '../types.js';

import outdent from 'outdent';

import {indent, getSandbox, getBuildConfig} from './esy';
import * as PackageManifest from '../package-manifest';
import * as Sandbox from '../sandbox/index.js';
import * as Common from './common.js';
import * as constants from '../constants.js';
import * as Config from '../config.js';
import * as Environment from '../environment.js';
import * as bashgen from '../bashgen.js';

import {PromiseQueue} from '../lib/Promise.js';
import * as path from '../lib/path.js';
import * as child from '../lib/child_process.js';
import * as fs from '../lib/fs.js';
import * as JSON from '../lib/json.js';
import * as Graph from '../lib/graph.js';

const currentEsyVersion = require('../../package.json').version;

export default async function esyRelease(
  ctx: CommandContext,
  invocation: CommandInvocation,
) {
  const {manifest} = await PackageManifest.read(ctx.sandboxPath);
  const config = await getBuildConfig(ctx);
  const sandbox = await getSandbox(ctx, {forRelease: true});

  const sandboxPath = config.sandboxPath;

  const releasePackagePath = path.join(sandboxPath, constants.RELEASE_TREE);

  const emitFile = file => Common.emitFileInto(releasePackagePath, file);

  const steps = createStepper(ctx);

  steps.addStep('Preparing release package', async () => {
    await fs.rmdir(releasePackagePath);
    await fs.mkdirp(releasePackagePath);

    const npmPackage = await deriveNpmPackageJson(manifest, releasePackagePath, 'bin');
    await emitFile({
      filename: ['package.json'],
      contents: JSON.stableStringifyPretty(npmPackage),
    });

    const exportConfig = Config.create({
      reporter: ctx.reporter,
      storePath: '$ESY__STORE',
      sandboxPath: '$ESY__SANDBOX',
      buildPlatform: 'linux',
    });

    await emitFile({
      filename: ['bin', 'sandbox-env'],
      contents: Environment.printEnvironment(
        Sandbox.getSandboxEnv(sandbox, exportConfig),
      ),
    });

    const esySrc = await fs.readFile(__filename);

    await emitFile({
      filename: ['bin', 'esy.js'],
      contents: esySrc,
    });
  });

  steps.addStep('Copying built artifacts into the release package', async () => {
    const queue = new PromiseQueue({concurrency: 20});
    const builds = Graph.toArray(sandbox.root);

    await Promise.all(
      builds.map(build =>
        queue.add(async () => {
          await Common.exportBuild(
            ctx,
            config,
            build,
            path.join(releasePackagePath, '_export'),
          );
        }),
      ),
    );
  });

  await steps.run();

  const releasePackagePathRel = path.relative(process.cwd(), releasePackagePath);

  ctx.reporter.info(outdent`
    Release created at "./${releasePackagePathRel}".
    You can "cd ./${releasePackagePathRel}" and run "npm publish".
  `);
}

function createStepper(ctx) {
  const steps: Array<(curr: number, total: number) => Promise<void>> = [];

  return {
    addStep(name, f) {
      steps.push(async (curr, total) => {
        ctx.reporter.step(curr, total, name);
        await f();
      });
    },

    async run() {
      let currentStep = 0;
      for (const step of steps) {
        await step(++currentStep, steps.length);
      }
    },
  };
}

/**
 * Derive npm release package.
 *
 * This strips all dependency info and add "bin" metadata.
 */
async function deriveNpmPackageJson(manifest, releasePackagePath, releaseType) {
  let copy = JSON.parse(JSON.stringify(manifest));

  // We don't manage dependencies with npm, esy is being installed via a
  // postinstall script and then it is used to manage release dependencies.
  copy.dependencies = {};
  copy.peerDependencies = {};
  copy.devDependencies = {};

  // Populate "bin" metadata.
  await fs.mkdirp(path.join(releasePackagePath, 'bin'));
  const binsToWrite = getSandboxCommands(releaseType, releasePackagePath, manifest);
  const packageJsonBins = {};
  for (let i = 0; i < binsToWrite.length; i++) {
    const toWrite = binsToWrite[i];
    await fs.writeFile(path.join(releasePackagePath, toWrite.path), toWrite.contents);
    await fs.chmod(path.join(releasePackagePath, toWrite.path), /* octal 0755 */ 493);
    packageJsonBins[toWrite.name] = toWrite.path;
  }
  copy.bin = packageJsonBins;

  // Add postinstall script
  copy.scripts.postinstall = `node ./bin/esy.js install-release`;

  return copy;
}

/**
 * Derive esy release package.
 */
async function deriveEsyPackageJson(manifest, releasePackagePath, releaseType) {
  const copy = JSON.parse(JSON.stringify(manifest));
  delete copy.dependencies.esy;
  delete copy.devDependencies.esy;
  return copy;
}

function getSandboxCommands(releaseType, releasePackagePath, manifest) {
  const commands = [];

  const commandsToRelease = getCommandsToRelease(manifest);
  if (commandsToRelease) {
    for (let i = 0; i < commandsToRelease.length; i++) {
      const commandName = commandsToRelease[i];
      const destPath = path.join('bin', commandName);
      commands.push({
        name: commandName,
        path: destPath,
        contents: createCommandWrapper(manifest, commandName),
      });
    }
  }

  // Generate sandbox entry command
  const sandboxEntryCommandName = getSandboxEntryCommandName(manifest.name);
  const destPath = path.join('bin', sandboxEntryCommandName);
  commands.push({
    name: sandboxEntryCommandName,
    path: destPath,
    contents: createCommandWrapper(manifest, sandboxEntryCommandName),
  });

  return commands;
}

function getCommandsToRelease(manifest) {
  return (
    manifest &&
    manifest.esy &&
    manifest.esy.release &&
    manifest.esy.release.releasedBinaries
  );
}

function createCommandWrapper(manifest, commandName) {
  const packageName = manifest.name;
  const sandboxEntryCommandName = getSandboxEntryCommandName(packageName);
  const packageNameUppercase = escapeBashVarName(manifest.name.toUpperCase());
  const binaryNameUppercase = escapeBashVarName(commandName.toUpperCase());
  const commandsToRelease = getCommandsToRelease(manifest) || [];
  const releasedBinariesStr = commandsToRelease
    .concat(sandboxEntryCommandName)
    .join(', ');

  const execute =
    commandName !== sandboxEntryCommandName
      ? outdent`
      if [ "$1" == "----where" ]; then
        which "${commandName}"
      else
        exec "${commandName}" "$@"
      fi
      `
      : outdent`
      if [[ "$1" == ""  ]]; then
        cat << EOF

      Welcome to ${packageName}

      The following commands are available: ${releasedBinariesStr}

      Note:

      - ${sandboxEntryCommandName} bash

        Starts a sandboxed bash shell with access to the ${packageName} environment.

        Running builds and scripts from within "${sandboxEntryCommandName} bash" will typically increase
        the performance as environment is already sourced.

      - <command name> ----where

        Prints the location of <command name>

        Example: ocaml ----where

      EOF
      else
        if [ "$1" == "bash" ]; then
          # Important to pass --noprofile, and --rcfile so that the user's
          # .bashrc doesn't run and the npm global packages don't get put in front
          # of the already constructed PATH.
          bash --noprofile --rcfile <(echo 'export PS1="[${packageName} sandbox] "')
        else
          echo "Invalid argument $1, type ${sandboxEntryCommandName} for help"
        fi
      fi
      `;

  return outdent`
    #!/bin/bash

    printError() {
      echo >&2 "ERROR:";
      echo >&2 "$0 command is not installed correctly. ";
      TROUBLESHOOTING="When installing <package_name>, did you see any errors in the log? "
      TROUBLESHOOTING="$TROUBLESHOOTING - What does (which <binary_name>) return? "
      TROUBLESHOOTING="$TROUBLESHOOTING - Please file a github issue on <package_name>'s repo."
      echo >&2 "$TROUBLESHOOTING";
    }

    if [ -z \${${packageNameUppercase}__ENVIRONMENTSOURCED__${binaryNameUppercase}+x} ]; then
      if [ -z \${${packageNameUppercase}__ENVIRONMENTSOURCED+x} ]; then
        ${bashgen.defineScriptDir}
        ${bashgen.defineEsyUtil}
        esyReleasePackageRoot=$(dirname "$SCRIPTDIR")
        export ESY__STORE="$(esyGetStorePathFromPrefix $esyReleasePackageRoot)"
        source "$SCRIPTDIR/sandbox-env"
        export ${packageNameUppercase}__ENVIRONMENTSOURCED="sourced"
        export ${packageNameUppercase}__ENVIRONMENTSOURCED__${binaryNameUppercase}="sourced"
      fi
      command -v $0 >/dev/null 2>&1 || {
        printError;
        exit 1;
      }
      ${execute}
    else
      printError;
      exit 1;
    fi

  `;
}

function getSandboxEntryCommandName(packageName: string) {
  return `${packageName}-esy-sandbox`;
}

function escapeBashVarName(str) {
  const map = {'.': 'd', _: '_', '-': 'h'};
  const replacer = match => (map.hasOwnProperty(match) ? '_' + map[match] : match);
  return str.replace(/./g, replacer);
}
