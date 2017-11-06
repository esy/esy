/**
 * @flow
 */

import type {Config, BuildTask, BuildSpec, EnvironmentVar} from './types';
import * as Task from './build-task';

export function getCommandEnv(
  task: BuildTask,
  config: Config<*>,
): Map<string, EnvironmentVar> {
  const env = new Map(task.env);
  env.delete('SHELL');
  return env;
}

export function getSandboxEnv(
  task: BuildTask,
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
    dependencies: new Map([[task.spec.name, task.spec]]),
    errors: task.spec.errors,
  };
  const {env} = Task.fromBuildSpec(spec, config);
  env.delete('SHELL');
  return env;
}
