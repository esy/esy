/**
 * Implementation of `esy release` process.
 *
 * Release types:
 *
 * **dev**: Dev releases perform everything on the client installer machine
 * (download, build).
 *
 * **pack**: Pack releases perform download and "pack"ing on the "server", and
 * then only builds will be performed on the client. This snapshots a giant
 * tarball of all dependencies' source files into the release.
 *
 * **bin**: Bin releases perform everything on "the server", and "the client"
 * installs a package consisting only of binary executables.
 *
 *                                     RELEASE PROCESS
 *
 *
 *
 *      ○ make release TYPE=dev        ○ make release TYPE=pack      ○─ make release TYPE=bin
 *      │                              │                             │
 *      ○ trivial configuration        ○ trivial configuration       ○ trivial configuration
 *      │                              │                             │
 *      ●─ Dev Release                 │                             │
 *      .                              │                             │
 *      .                              │                             │
 *      ○ npm install                  │                             │
 *      │                              │                             │
 *      ○ Download dependencies        ○ Download dependencies       ○ Download dependencies
 *      │                              │                             │
 *      ○ Pack all dependencies        ○ Pack all dependencies       ○ Pack all dependencies
 *      │ into single tar+Makefile     │ into single tar+Makefile    │ into single tar+Makefile
 *      │                              │                             │
 *      │                              ●─ Pack Release               │
 *      │                              .                             │
 *      │                              .                             │
 *      │                              ○ npm install                 │
 *      │                              │                             │
 *      ○─ Build Binaries              ○─ Build Binaries             ○─ Build Binaries
 *      │                              │                             │
 *      │                              │                             ●─ Bin Release
 *      │                              │                             .
 *      │                              │                             .
 *      │                              │                             ○ npm install
 *      │                              │                             │
 *      ○─ Npm puts binaries in path   ○─ Npm puts binaries in path  ○─ Npm puts binaries in path.
 *
 *
 * For 'bin' releases, it doesn't make sense to use any build cache, so the `Makefile`
 * at the root of this project substitutes placeholders in the generated binary
 * wrappers indicating where the build cache should be.
 *
 * > Relocating: "But aren't binaries built with particular paths encoded? How do
 * we distribute binaries that were built on someone else's machine?"
 *
 * That's one of the main challenges with distributing binaries. But most
 * applications that assume hard coded paths also allow overriding that hard
 * coded-ness in a wrapper script.  (Merlin, ocamlfind, and many more). Thankfully
 * we can have binary releases wrap the intended binaries that not only makes
 * Windows compatibility easier, but that also fixes many of the problems of
 * relocatability.
 *
 * > NOTE: Many binary npm releases include binary wrappers that correctly resolve
 * > the binary depending on platform, but they use a node.js script wrapper. The
 * > problem with this is that it can *massively* slow down build times when your
 * > builds call out to your binary which must first boot an entire V8 runtime. For
 * > `reason-cli` binary releases, we create lighter weight shell scripts that load
 * > in a fraction of the time of a V8 environment.
 *
 * The binary wrapper is generally helpful whether or *not* you are using
 * prereleased binaries vs. compiling from source, and whether or not you are
 * targeting linux/osx vs. Windows.
 *
 * When using Windows:
 *   - The wrapper script allows your linux and osx builds to produce
 *     `executableName.exe` files while still allowing your windows builds to
 *     produce `executableName.exe` as well.  It's usually a good idea to name all
 *     your executables `.exe` regardless of platform, but npm gets in the way
 *     there because you can't have *three* binaries named `executableName.exe`
 *     all installed upon `npm install -g`. Wrapper scripts to the rescue.  We
 *     publish two script wrappers per exposed binary - one called
 *     `executableName` (a shell script that works on Mac/Linux) and one called
 *     `executableName.cmd` (Windows cmd script) and npm will ensure that both are
 *     installed globally installed into the PATH when doing `npm install -g`, but
 *     in windows command line, `executableName` will resolve to the `.cmd` file.
 *     The wrapper script will execute the *correct* binary for the platform.
 * When using binaries:
 *   - The wrapper script will typically make *relocated* binaries more reliable.
 * When building pack or dev releases:
 *   - Binaries do not exist at the time the packages are installed (they are
 *     built in postinstall), but npm requires that bin links exists *at the time*
 *     of installation. Having a wrapper script allows you to publish `npm`
 *     packages that build binaries, where those binaries do not yet exist, yet
 *     have all the bin links installed correctly at install time.
 *
 * The wrapper scripts are common practice in npm packaging of binaries, and each
 * kind of release/development benefits from those wrappers in some way.
 *
 * TODO:
 *  - Support local installations of <package_name> which would work for any of
 *    the three release forms.
 *    - With the wrapper script, it might already even work.
 *  - Actually create `.cmd` launcher.
 *
 * NOTES:
 *
 *  We maintain two global variables that wrappers consult:
 *
 *  - `<PACKAGE_NAME>_ENVIRONMENT_SOURCED`: So that if one wrapped binary calls
 *    out to another we don't need to repeatedly setup the path.
 *
 *  - `<PACKAGE_NAME>_ENVIRONMENT_SOURCED_<binary_name>`: So that if
 *    `<binary_name>` ever calls out to the same `<binary_name>` script we know
 *    it's because the environment wasn't sourced correctly and therefore it is
 *    infinitely looping.  An early check detects this.
 *
 *  Only if we even need to compute the environment will we do the expensive work
 *  of sourcing the paths. That makes it so merlin can repeatedly call
 *  `<binary_name>` with very low overhead for example.
 *
 *  If the env didn't correctly load and no `<binary_name>` shadows it, this will
 *  infinitely loop. Therefore, we put a check to make sure that no
 *  `<binary_name>` calls out to ocaml again. See
 *  `<PACKAGE_NAME>_ENVIRONMENT_SOURCED_<binary_name>`
 *
 *  @flow
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
