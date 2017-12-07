/**
 * @flow
 */

import type {Config, Sandbox, BuildTask, BuildSpec, EnvironmentBinding} from '../types';
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
export function getCommandEnv(sandbox: Sandbox, config: Config<*>): Map<string, string> {
  const task = Task.fromSandbox(sandbox, config, {
    includeDevDependencies: true,
  });
  const envMap = Env.evalEnvironment(task.env);
  envMap.delete('SHELL');
  return envMap;
}

/**
 * Sandbox env represent the environment which includes the root package.
 *
 * Mainly used to test the package as it's like it being installed.
 */
export function getSandboxEnv(sandbox: Sandbox, config: Config<*>): Map<string, string> {
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
    dependencies: new Map([[sandbox.root.name, sandbox.root]]),
    errors: sandbox.root.errors,
  };
  const {env} = Task.fromBuildSpec(spec, config);
  const envMap = Env.evalEnvironment(env);
  envMap.delete('SHELL');
  return envMap;
}
