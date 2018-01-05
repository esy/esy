/**
 * @flow
 */

import * as fs from './lib/fs';
import * as child_process from './lib/child_process';
import * as os from 'os';
import * as path from 'path';
import * as bashgen from './bashgen';
import outdent from 'outdent';
import {RELEASE_TREE, CURRENT_ESY_EXECUTABLE} from './constants';
import * as PackageManifest from './package-manifest.js';

type ReleaseType = 'dev' | 'pack' | 'bin';

type BuildReleaseConfig = {
  type: ReleaseType,
  version: string,
  sandboxPath: string,
  esyVersionForDevRelease: string,
};

function escapeBashVarName(str) {
  const map = {'.': 'd', _: '_', '-': 'h'};
  const replacer = match => (map.hasOwnProperty(match) ? '_' + map[match] : match);
  return str.replace(/./g, replacer);
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
        esyReleasePackageRoot=$(dirname "$SCRIPTDIR")
        export ESY_EJECT__PREFIX="$esyReleasePackageRoot"
        esySandboxEnv="$esyReleasePackageRoot/r/build-eject/sandbox-env"
        source "$esySandboxEnv"
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
  await fs.mkdirp(path.join(releasePackagePath, '.bin'));
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
  copy.scripts.postinstall = `./bin/esyBuildRelease ${releaseType} install`;

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

async function putJson(filename, manifest) {
  await fs.writeFile(filename, JSON.stringify(manifest, null, 2), 'utf8');
}

async function verifyBinSetup(sandboxPath, manifest) {
  const binDirExists = await fs.exists(path.join(sandboxPath, '.bin'));
  if (binDirExists) {
    throw new Error(
      outdent`
      Run make clean first. The release script needs to be in charge of generating the binaries.
      Found existing binaries dir .bin. This should not exist. Release script creates it.
    `,
    );
  }
  if (manifest.bin) {
    throw new Error(
      outdent`
      Run make clean first. The release script needs to be in charge of generating the binaries.
      package.json has a bin field. It should have a "commandsToRelease" field instead - a list of released binary names.
    `,
    );
  }
}

function getSandboxEntryCommandName(packageName: string) {
  return `${packageName}-esy-sandbox`;
}

function getSandboxCommands(releaseType, releasePackagePath, manifest) {
  const commands = [];

  const commandsToRelease = getCommandsToRelease(manifest);
  if (commandsToRelease) {
    for (let i = 0; i < commandsToRelease.length; i++) {
      const commandName = commandsToRelease[i];
      const destPath = path.join('.bin', commandName);
      commands.push({
        name: commandName,
        path: destPath,
        contents: createCommandWrapper(manifest, commandName),
      });
    }
  }

  // Generate sandbox entry command
  const sandboxEntryCommandName = getSandboxEntryCommandName(manifest.name);
  const destPath = path.join('.bin', sandboxEntryCommandName);
  commands.push({
    name: sandboxEntryCommandName,
    path: destPath,
    contents: createCommandWrapper(manifest, sandboxEntryCommandName),
  });

  return commands;
}

async function putExecutable(filename, contents) {
  await fs.writeFile(filename, contents);
  await fs.chmod(filename, /* octal 0755 */ 493);
}

function getReleaseTag(config) {
  const tag = config.type === 'bin' ? `bin-${os.platform()}` : config.type;
  return tag;
}

/**
 * Builds the release from within the rootDirectory/package/ directory created
 * by `npm pack` command.
 */
export async function buildRelease(config: BuildReleaseConfig) {
  const releaseType = config.type;
  const releaseTag = getReleaseTag(config);

  const sandboxPath = config.sandboxPath;

  const releasePackagePath = path.join(sandboxPath, RELEASE_TREE, releaseTag);
  const releaseSandboxPath = path.join(releasePackagePath, 'r');

  // init releaseSandboxPath
  const tarFilename = await child_process.spawn('npm', ['pack'], {cwd: sandboxPath});
  await child_process.spawn('tar', ['xzf', tarFilename]);
  await fs.rmdir(releasePackagePath);
  await fs.mkdirp(releasePackagePath);
  await fs.rename(path.join(sandboxPath, 'package'), releaseSandboxPath);
  await fs.unlink(tarFilename);

  const {manifest} = await PackageManifest.read(releaseSandboxPath);
  await verifyBinSetup(sandboxPath, manifest);

  const npmPackage = await deriveNpmPackageJson(
    manifest,
    releasePackagePath,
    releaseType,
  );
  await putJson(path.join(releasePackagePath, 'package.json'), npmPackage);

  const esyPackage = await deriveEsyPackageJson(
    manifest,
    releasePackagePath,
    releaseType,
  );
  await fs.mkdirp(releaseSandboxPath);
  await putJson(path.join(releaseSandboxPath, 'package.json'), esyPackage);

  if (manifest.esy.release.deleteFromBinaryRelease != null) {
    const patterns = manifest.esy.release.deleteFromBinaryRelease.join('\n');
    await fs.writeFile(
      path.join(releasePackagePath, 'deleteFromBinaryRelease'),
      patterns,
    );
  }

  const BIN = ['realpath.sh', 'esyConfig.sh', 'esyRuntime.sh', 'esyBuildRelease'];

  await fs.mkdirp(path.join(releasePackagePath, 'bin'));
  const binDir = path.dirname(CURRENT_ESY_EXECUTABLE);
  await Promise.all(
    BIN.map(async name => {
      await fs.copy(path.join(binDir, name), path.join(releasePackagePath, 'bin', name));
    }),
  );

  // Now run prerelease.sh, we reset $ESY__SANDBOX as it's going to call esy
  // recursively but leave $ESY__STORE & $ESY__LOCAL_STORE in place.
  const env = {
    ...process.env,
    ESY__COMMAND: CURRENT_ESY_EXECUTABLE,
  };
  delete env.ESY__SANDBOX;
  await child_process.spawn('bin/esyBuildRelease', [releaseType, 'prepare'], {
    env,
    cwd: releasePackagePath,
    stdio: 'inherit',
  });

  console.log(outdent`
    *** Release package created

        Location: ${path.relative(process.cwd(), releasePackagePath)}
        Release Type: ${releaseType}

  `);
}
