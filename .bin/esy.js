#!/usr/bin/env node

var esyEnv = require('./esyEnv.js');


/**
 * Each package can configure exportedEnvVars with:
 *
 * (object key is environment variable name)
 *
 * val: string
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
 * compilation - so it sets the scope flag to "local"
 *
 * "CC_FLAG": {
 *   "val": "-opt 0",
 *   "scope": "local"
 * }
 *
 * This allows us to create a package `my-app` that depends on `my-package`
 * (which depends on `my-compiler`) but that doesn't automatically compile
 * itself with the same flags that `my-package` used.
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
 * Each of the scopes are writing to completely different locations.  "global"
 * is writing to the global namespace, "local" is writing to that particular
 * packages local namespace which "shadows" the global. "export" is writing to
 * the packages' *immediate* dependencies' *local* namespace.
 *
 * Priority of scope visibility is as follows: You see the global scope
 * (consisting of all global variables set by your transitive dependencies)
 * then you see the exported scope of your direct dependencies, shadowing any
 * global scope and then you see your local scope, which shaddows everything
 * else. Each time you shadow a scope, you can reference the lower priority
 * scope *while* shadowing. Just like you can do the following in ML, to
 * redefine addition in terms of addition that was in global scope.
 *
 *
 *   open Pervasives;
 *   let (+) = fun (a, b) => a + b;
 *
 *   "CC_FLAG": {
 *     "val": "-opt 3 $CC_FLAG",
 *     "scope": "local"
 *   }
 *
 *
 * In fact, all of this configuration could/should be replaced by a real
 * language. The package builder would then just be something that concatenates
 * files together in a predictable order.
 *
 * Note: "export" and "global" *imply* "local" as well. You either want local
 * visibility of a variable, and don't want to export it - or you want local
 * visibility and you also want to export it - you seldom want to export
 * without local visibility.
 *           
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
 * Need to change this to climb to closest package.json.
 */
var curDir = process.cwd();

var builtInCommands = {
  "build": true,
  "shell": true,
  "deshell": true
};
var actualArgs = process.argv.slice(2);

let envForThisPackageScripts = esyEnv.getRelativizedEnv(curDir, curDir);
if (actualArgs.length === 0) {
  // It's just a status command. Print the command that would be
  // used to setup the environment along with status of
  // the build processes, staleness, package validity etc.
  console.log(esyEnv.print(envForThisPackageScripts));
} else {
  var builtInCommand = builtInCommands[actualArgs[0]];
  if (builtInCommand) {
    builtInCommand.apply(null, process.argv.slice(3));
  } else {
    let command = actualArgs.join(' ');
  }
}

