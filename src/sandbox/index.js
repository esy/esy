/**
 * @flow
 */

import type {Config, Sandbox, BuildTask, BuildSpec, Environment} from '../types';
import * as Task from '../build-task';
import * as M from '../package-manifest';
import * as Env from '../environment.js';

/**
 * Command env is used to execute arbitrary commands within the sandbox
 * environment.
 *
 * Mainly used for dev, for example you'd want Merlin to be run
 * within this environment.
 */
export function getCommandEnv(sandbox: Sandbox, config: Config<*>): Environment {
  const task = Task.fromSandbox(sandbox, config, {
    includeDevDependencies: true,
  });
  const commandEnv = task.env.filter(item => item.name !== 'SHELL');
  return commandEnv;
}

/**
 * Sandbox env represent the environment which includes the root package.
 *
 * Mainly used to test the package as it's like it being installed.
 */
export function getSandboxEnv(sandbox: Sandbox, config: Config<*>): Environment {
  const spec: BuildSpec = {
    id: '__sandbox__',
    idInfo: null,
    name: '__sandbox__',
    version: '0.0.0',
    buildCommand: [],
    installCommand: [],
    exportedEnv: {},
    sourcePath: '',
    packagePath: '',
    sourceType: 'root',
    buildType: 'out-of-source',
    dependencies: new Map([[sandbox.root.id, sandbox.root]]),
    errors: sandbox.root.errors,
  };
  const task = Task.fromBuildSpec(spec, config);
  const sandboxEnv = task.env.filter(item => item.name !== 'SHELL');
  return sandboxEnv;
}
