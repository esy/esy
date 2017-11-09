/**
 * @flow
 */

import type {Config, Sandbox, BuildTask, BuildSpec, EnvironmentVar} from './types';
import * as Task from './build-task';

/**
 * Command env is used to execute arbitrary commands within the sandbox
 * environment.
 *
 * Mainly used for dev, for example you'd want Merlin to be run
 * within this environment.
 */
export function getCommandEnv(
  sandbox: Sandbox,
  config: Config<*>,
): Map<string, EnvironmentVar> {
  const task = Task.fromSandbox(sandbox, config, {
    includeDevDependencies: true,
  });
  const env = new Map(task.env);
  // we are not interested in overriden $SHELL here as user might have its own
  // customizations in .profile or shell's .rc files.
  env.delete('SHELL');
  return env;
}

/**
 * Sandbox env represent the environment which includes the root package.
 *
 * Mainly used to test the package as it's like it being installed.
 */
export function getSandboxEnv(
  sandbox: Sandbox,
  config: Config<*>,
): Map<string, EnvironmentVar> {
  const spec: BuildSpec = {
    id: '__sandbox__',
    name: '__sandbox__',
    version: '0.0.0',
    buildCommand: [],
    installCommand: [],
    exportedEnv: {},
    sourcePath: '',
    sourceType: 'root',
    buildType: 'out-of-source',
    shouldBePersisted: false,
    dependencies: new Map([[sandbox.root.name, sandbox.root]]),
    errors: sandbox.root.errors,
  };
  const {env} = Task.fromBuildSpec(spec, config);
  env.delete('SHELL');
  return env;
}
