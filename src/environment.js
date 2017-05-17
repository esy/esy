/**
 * @flow
 */

import type {BuildEnvironment, EnvironmentVar} from './types';
import * as os from 'os';

// X platform newline
const EOL = os.EOL;

export function fromEntries(entries: EnvironmentVar[]): BuildEnvironment {
  const env = new Map();
  for (const entry of entries) {
    env.set(entry.name, entry);
  }
  return env;
}

export function merge(
  items: BuildEnvironment[],
  merger: (BuildEnvironment, Array<EnvironmentVar>) => BuildEnvironment,
): BuildEnvironment {
  return items.reduce(
    (env, currentEnv) => merger(env, Array.from(currentEnv.values())),
    new Map(),
  );
}

export function printEnvironment(env: BuildEnvironment) {
  const groupsByBuild = new Map();

  for (const item of env.values()) {
    const key = item.spec != null ? item.spec.id : 'Esy Sandbox';
    const header = item.spec != null
      ? `${item.spec.name}@${item.spec.version} ${item.spec.sourcePath}`
      : 'Esy Sandbox';
    let group = groupsByBuild.get(key);
    if (group == null) {
      group = {header, env: []};
      groupsByBuild.set(key, group);
    }
    group.env.push(item);
  }

  return Array.from(groupsByBuild.values())
    .map(group => {
      const headerLines = [`# ${group.header}`];
      // TODO: add error rendering here
      // const errorLines = group.errors.map(err => {
      //   return '# [ERROR] ' + err;
      // });
      const envVarLines = group.env.map(item => {
        // TODO: escape " in values
        const exportLine = `export ${item.name}="${item.value}"`;
        return exportLine;
      });
      return headerLines.concat(envVarLines).join(EOL);
    })
    .join(EOL);
}
