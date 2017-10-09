/**
 * @flow
 */

require('babel-polyfill');

// TODO: This is a hack, we need to find a way to solve that more elegantly. But
// for not this is required as we redirected stderr to stdout and those
// possible deprecation warnings can really hurt and make things difficult to
// debug.
// $FlowFixMe: fix me
process.noDeprecation = true;

import type {BuildSandbox, BuildTask, BuildPlatform} from '../types';

import * as os from 'os';
import * as fs from 'fs';
import * as pfs from '../lib/fs';
import * as child_process from '../lib/child_process';
import loudRejection from 'loud-rejection';
import outdent from 'outdent';
import userHome from 'user-home';
import * as path from 'path';
import chalk from 'chalk';
import {settings as configureObservatory} from 'observatory';
import * as Env from '../environment';
import * as Task from '../build-task';
import * as Config from '../build-config';
import * as Sandbox from '../build-sandbox';
import * as EsyOpam from '@esy-ocaml/esy-opam';

/**
 * Each package can configure exportedEnvVars with:
 *
 * (object key is environment variable name)
 *
 * val: string
 *
 * scope: In short:
 *    "local": Can be seen by this package at build time, shadows anything
 *    configured by dependencies.
 *    "export": Seen by immediate dependers during their build times, and
 *    shadows any global variables those immediate dependers can see at build
 *    time.
 *    "global": Seen by all packages that have a transitive linktime dependency
 *    on our package.
 *
 *    You can or them together: "local|export", "local|global".
 *
 * Example:
 *
 *   If you are publishing a binary to all transitive dependers, you'd do:
 *
 *     "PATH": {
 *       "val": "PATH:$PATH",
 *       "scope": "global"
 *     }
 *
 *   You wouldn't necessarily use a "local" scope because your package that
 *   builds the resulting binary doesn't care about seeing that binary.
 *
 *   Similarly, if you build library artifacts, you don't care about *seeing*
 *   those library artifacts as the library that is building them.
 *
 *
 *     "FINDLIB": {
 *       "val": "$MY_PACKAGE__LIB:$FINDLIB",
 *       "scope": "export"
 *     }
 *
 * VISIBILITY:
 * -------------
 *
 * Consider that a package my-compiler has defines a variable CC_FLAG. It would
 * normally publish some default flag with a "global" scope so that everyone
 * who transitively depends on it can see the default.
 *
 * "CC_FLAG": {
 *   "val": "-default-flag",
 *   "scope": "global"
 * }
 *
 * Then we want to be able to create a package `my-package` that depends on
 * `my-compiler`, which wants to override those flags for its own package
 * compilation - so it sets the scope flag to "local". The local scope
 * shadows the global scope, and the new value is only observed by
 * `my-package`.
 *
 * "CC_FLAG": {
 *   "val": "-opt 0",
 *   "scope": "local"
 * }
 *
 * In the same way that let bindings shadow global bindings, yet can reference
 * the global one in the definition of the local one, the same is true of local
 * environment variables.
 *
 *   let print_string = fun(s) => print_string(s + "!!!");
 *
 *   // Analogous to
 *   "CC_FLAG": {
 *     "val": "-opt 0 $CC_FLAG",
 *     "scope": "local"
 *   }
 *
 *
 * Local scopes allow us to create a package `my-app` that depends on
 * `my-package` (which in turn depends on `my-compiler`) such that `my-app`
 * doesn't observe the conpiler flags that its dependency (`my-package`) used.
 *
 * Though, in other cases, we *do* want configured flags to be visible.
 * Imagine making a package called `add-opt-flags`, which only has a
 * `package.json` that configures optimized compiler flags. If you directly
 * depend on `add-opt-flags`, you get all the flags added to your package.
 * `add-opt-flags` would configure the variable like:
 *
 * "CC_FLAG": {
 *   "val": "-opt 3",
 *   "scope": "export"
 * }
 *
 * If `your-app` depends on `add-opt-flags`, you would get all the flags set by
 * `add-opt-flags`, but if `app-store` depends on `your-app`, `app-store`
 * wouldn't have opt flags added automatically.
 *
 *
 * Priority of scope visibility is as follows: You see the global scope
 * (consisting of all global variables set by your transitive dependencies)
 * then you see the exported scope of your direct dependencies, shadowing any
 * global scope and then you see your local scope, which shaddows everything
 * else. Each time you shadow a scope, you can reference the lower priority
 * scope *while* shadowing. Just like you can do the following in ML, to
 * redefine addition in terms of addition that was in global scope.
 *
 * A language analogy would be the assumption that every package has an implicit
 * "opening" of its dependencies' exports, to bring them into scope.
 *
 *   open GlobalScopeFromAllTransitiveRuntimeDependencies;
 *   open AllImmediateDependencies.Exports;
 *
 *   let myLocalVariable = expression(in, terms, of, everything, above);
 *
 * In fact, all of this configuration could/should be replaced by a real
 * language. The package builder would then just be something that concatenates
 * files together in a predictable order.
 *
 * WHO CAN WRITE:
 * -------------
 *
 *  When thinking about conflicts, it helps to recall that different scopes are
 *  actually writing to different locations that shadow in convenient ways.
 *  We need some way to control exclusivity of writing these env vars to prevent
 *  conflicts. The current implementaiton just has a single exclusive:
 *  true/false flag and it doesn't take into account scope.
 */

/**
 * Detect the default build platform based on the current OS.
 */
const defaultBuildPlatform: BuildPlatform =
  process.platform === 'darwin' ? 'darwin' :
  process.platform === 'linux' ? 'linux' :
  'linux';

/**
 * This is temporary, mostly here for testing. Soon, esy will automatically
 * create build ejects for all valid platforms.
 */
function determineBuildPlatformFromArgument(arg): BuildPlatform {
  if (arg === '' || arg === null || arg === undefined) {
    return defaultBuildPlatform;
  } else {
    if (arg === 'darwin') {
      return 'darwin'
    } else if (arg === 'linux') {
      return 'linux'
    } else if (arg === 'cygwin') {
      return 'cygwin'
    }
    throw new Error('Specified build platform ' + arg + ' is invalid: Pass one of "linux", "cygwin", or "darwin"')
  }
}

function formatError(message: string, stack?: string) {
  let result = `${chalk.red('ERROR')} ${message}`;
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

async function getBuildSandbox(sandboxPath): Promise<BuildSandbox> {
  const sandbox = await Sandbox.fromDirectory(sandboxPath);
  if (sandbox.root.errors.length > 0) {
    sandbox.root.errors.forEach(error => {
      console.log(formatError(error.message));
    });
    process.exit(1);
  }
  return sandbox;
}

const actualArgs = process.argv.slice(2);
// TODO: Need to change this to climb to closest package.json.
const sandboxPath = process.cwd();

/**
 * To relocate binary artifacts, we need to replace all build-time paths that
 * occur in build artifacts with install-time paths, which very well may be on
 * a different computer even. In order to do so safely, we need to never change
 * the length of the paths (otherwise we would corrupt the binaries).
 * Therefore, it's beneficial to reserve as much padding in the build path as
 * possible, without the path to ocamlrun ever exceeding the maximum allowed
 * shebang length (since scripts will have a shebang to the full path to
 * ocamlrun). The maximum line length is 127 (on most linuxes). Mac OS is a
 * little more forgiving with the length restriction, so we plan for the worst
 * (Linux).
 *
 *        This will be replaced by the actual      This must remain.
 *        install location.
 *       +------------------------------+  +--------------------------------+
 *      /                                \/                                  \
 *   #!/path/to/rel/store___padding____/i/ocaml-4.02.3-d8a857f3/bin/ocamlrun
 *
 * The goal is to make this shebang string exactly 127 characters long (maybe a
 * little less to allow room for some other shebangs like `ocamlrun.opt` etc?)
 *
 * It is optimal to make this path as long as possible (because the
 * installation location might be embedded deep in the file system), but no
 * longer than 127 characters. It is optimal to minimize the portion of this
 * shebang consumed by the "ocaml-4.02.3-d8a857f3/bin/ocamlrun" portion, so
 * that more of that 127 can act as a padding.
 */
var desiredShebangPathLength = 127 - "!#".length;
var pathLengthConsumedByOcamlrun = "/i/ocaml-n.00.0-########/bin/ocamlrun".length;
var desiredEsyEjectStoreLength = desiredShebangPathLength - pathLengthConsumedByOcamlrun;

function buildConfigForBuildCommand(buildPlatform: BuildPlatform) {
  const storePath =
    process.env.ESY__STORE || path.join(userHome, '.esy', Config.ESY_STORE_VERSION);
  return Config.createConfig({storePath, sandboxPath, buildPlatform});
}


/**
 * Note that Makefile based builds defers exact locations of sandbox and store
 * to some later point because ejected builds can be transfered to other
 * machines.
 *
 * That means that build env is generated in a way which can be configured later
 * with `$ESY_EJECT__SANDBOX` and `$ESY__STORE` environment variables.
 */
function buildConfigForBuildEjectCommand(buildPlatform: BuildPlatform) {
  const STORE_PATH = '$ESY_EJECT__STORE';
  const SANDBOX_PATH = '$ESY_EJECT__SANDBOX';
  const buildConfig: BuildConfig = Config.createConfig({
    storePath: STORE_PATH,
    sandboxPath: SANDBOX_PATH,
    buildPlatform,
  });
  return buildConfig;
}

async function buildCommand(sandboxPath, _commandName) {
  const config = buildConfigForBuildCommand(defaultBuildPlatform);
  const builder = require('../builders/simple-builder');

  const observatory = configureObservatory({
    prefix: chalk.green('  → '),
  });

  const loggingHandlers = new Map();
  function getReporterFor(task) {
    let handler = loggingHandlers.get(task.id);
    if (handler == null) {
      const version = chalk.grey(`@ ${task.spec.version}`);
      handler = observatory.add(`${task.spec.name} ${version}`);
      loggingHandlers.set(task.id, handler);
    }
    return handler;
  }

  const sandbox = await getBuildSandbox(sandboxPath);
  const task: BuildTask = Task.fromBuildSandbox(sandbox, config);
  const failures = [];
  await builder.build(task, sandbox, config, (task, status) => {
    if (status.state === 'in-progress') {
      getReporterFor(task).status('building...');
    } else if (status.state === 'success') {
      const {timeEllapsed} = status;
      if (timeEllapsed != null) {
        getReporterFor(task).done('BUILT').details(`in ${timeEllapsed / 1000}s`);
      } else if (!task.spec.shouldBePersisted) {
        getReporterFor(task).done('BUILT').details(`unchanged`);
      }
    } else if (status.state === 'failure') {
      failures.push({task, error: status.error});
      getReporterFor(task).fail('FAILED');
    }
  });
  for (const failure of failures) {
    const {error} = failure;
    if (error.logFilename) {
      const {logFilename} = (error: any);
      if (!failure.task.spec.shouldBePersisted) {
        const logContents = fs.readFileSync(logFilename, 'utf8');
        console.log(
          outdent`

            ${chalk.red('FAILED')} ${failure.task.spec.name}, see log for details:

            ${chalk.red(indent(logContents, '  '))}
            `,
        );
      } else {
        console.log(
          outdent`

            ${chalk.red('FAILED')} ${failure.task.spec.name}, see log for details:
              ${logFilename}

            `,
        );
      }
    } else {
      console.log(
        outdent`

        ${chalk.red('FAILED')} ${failure.task.spec.name}:
          ${failure.error}

        `,
      );
    }
  }
}

async function buildEjectCommand(
  sandboxPath,
  _commandName,
  _buildEjectPath,
  buildPlatformArg,
) {
  const buildPlatform: BuildPlatform = determineBuildPlatformFromArgument(buildPlatformArg);
  const buildEject = require('../builders/makefile-builder');
  const sandbox = await getBuildSandbox(sandboxPath);
  const buildConfig = buildConfigForBuildEjectCommand(buildPlatform);
  buildEject.renderToMakefile(
    sandbox,
    path.join(sandboxPath, 'node_modules', '.cache', '_esy', 'build-eject'),
    buildConfig,
  );
}

const AVAILABLE_RELEASE_TYPE = ['dev', 'pack', 'bin'];

async function releaseCommand(sandboxPath, _commandName, type, ...args) {
  if (type == null) {
    throw new Error('esy release: provide type');
  }
  if (AVAILABLE_RELEASE_TYPE.indexOf(type) === -1) {
    throw new Error(
      `esy release: invalid release type, must be one of: ${AVAILABLE_RELEASE_TYPE.join(', ')}`,
    );
  }

  const releaseTag = type === 'bin' ? `bin-${os.platform()}` : type;
  const outputPath = path.join(sandboxPath, '_release', releaseTag);

  // Strip all dev metadata and make sure we see what npm registry would see.
  // We use `npm pack` for that.
  const tarFilename = await child_process.spawn('npm', ['pack'], {cwd: sandboxPath});
  await child_process.spawn('tar', ['xzf', tarFilename]);
  await pfs.mkdirp(path.dirname(outputPath));
  await pfs.rmdir(outputPath);
  await pfs.rename(path.join(sandboxPath, 'package'), outputPath);
  await pfs.unlink(tarFilename);

  // Copy esyrelease.js executable over to release package.
  const esyReleaseCommandOrigin = require.resolve('./esyrelease.js');
  const esyReleaseCommandDest = path.join(outputPath, '_esy', 'esyrelease.js');
  await pfs.mkdirp(path.dirname(esyReleaseCommandDest));
  await pfs.copy(esyReleaseCommandOrigin, esyReleaseCommandDest);

  const pkg = await pfs.readJson(path.join(sandboxPath, 'package.json'));
  const env = {
    ...process.env,
    VERSION: pkg.version,
    TYPE: type,
  };
  const onData = chunk => {
    process.stdout.write(chunk);
  };
  await child_process.spawn(
    process.argv[0],
    ['-e', 'require("./_esy/esyrelease.js").buildRelease()'],
    {env, cwd: outputPath},
    onData,
  );
}

async function importOpamCommand(
  sandboxPath,
  _commandName,
  packageName,
  packageVersion,
  opamFilename,
) {
  if (opamFilename == null) {
    error(`usage: esy import-opam PACKAGENAME PACKAGEVERSION OPAMFILENAME`);
  }
  const opamData = await pfs.readFile(opamFilename);
  const opam = EsyOpam.parseOpam(opamData);
  const packageJson = EsyOpam.renderOpam(packageName, packageVersion, opam);
  // We inject "ocaml" into devDependencies as this is something which is have
  // to be done usually.
  packageJson.devDependencies = {
    ...packageJson.devDependencies,
    ocaml: 'esy-ocaml/ocaml#esy',
  };
  console.log(JSON.stringify(packageJson, null, 2));
}

const builtInCommands = {
  'build-eject': buildEjectCommand,
  build: buildCommand,
  release: releaseCommand,
  'import-opam': importOpamCommand,
};

function indent(string, indent) {
  return string.split('\n').map(line => indent + line).join('\n');
}

/**
 * CLI accepts
 * esy your command here
 * esy install
 * esy build
 * esy build-eject
 * esy build-eject buildPlatform  # Unsupported, temporary, for debugging purposes.
 * ... other yarn commands.
 */
async function main() {
  if (actualArgs.length === 0) {
    // TODO: It's just a status command. Print the command that would be
    // used to setup the environment along with status of
    // the build processes, staleness, package validity etc.
    const sandbox = await getBuildSandbox(sandboxPath);
    const config = buildConfigForBuildCommand(defaultBuildPlatform);
    const task = Task.fromBuildSandbox(sandbox, config, {exposeOwnPath: true});
    // Sandbox env is more strict than we want it to be at runtime, filter
    // out $SHELL overrides.
    task.env.delete('SHELL');
    console.log(Env.printEnvironment(task.env));
  } else {
    const builtInCommandName = actualArgs[0];
    const builtInCommand = builtInCommands[builtInCommandName];
    if (builtInCommand) {
      await builtInCommand(sandboxPath, ...process.argv.slice(3));
    } else {
      console.error(`unknown command: ${builtInCommandName}`);
    }
  }
}

main().catch(error);
loudRejection();
