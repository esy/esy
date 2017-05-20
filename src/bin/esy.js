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

import type {BuildSandbox, BuildTask} from '../types';

import * as fs from 'fs';
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
const storePath =
  process.env.ESY__STORE ||
  path.join(userHome, '.esy', `store-${Config.ESY_STORE_VERSION}`);
const config = Config.createConfig({storePath, sandboxPath});

async function buildCommand(sandboxPath) {
  const builder = require('../builders/simple-builder');

  const observatory = configureObservatory({
    prefix: chalk.green('  → '),
  });

  const loggingHandlers = new Map();
  function getReporterFor(task) {
    let handler = loggingHandlers.get(task.id);
    if (handler == null) {
      handler = observatory.add(task.spec.name);
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

async function buildEjectCommand(sandboxPath) {
  const buildEject = require('../builders/makefile-builder');
  const sandbox = await getBuildSandbox(sandboxPath);
  buildEject.renderToMakefile(
    sandbox,
    path.join(sandboxPath, 'node_modules', '.cache', '_esy', 'build-eject'),
  );
}

const builtInCommands = {
  'build-eject': buildEjectCommand,
  build: buildCommand,
};

function indent(string, indent) {
  return string.split('\n').map(line => indent + line).join('\n');
}

async function main() {
  if (actualArgs.length === 0) {
    // TODO: It's just a status command. Print the command that would be
    // used to setup the environment along with status of
    // the build processes, staleness, package validity etc.
    const sandbox = await getBuildSandbox(sandboxPath);
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
