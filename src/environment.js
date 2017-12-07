/**
 * @flow
 */

import type {Environment, EnvironmentBinding} from './types';

import * as shell from './lib/shell.js';
import * as os from 'os';

// X platform newline
const EOL = os.EOL;

export function fromEntries(entries: EnvironmentBinding[]): Environment {
  return entries;
}

export function printEnvironment(env: Environment) {
  const groupsByBuild = new Map();

  const groups = [];

  for (const item of env) {
    const header =
      item.origin != null
        ? `${item.origin.name}@${item.origin.version} ${item.origin.packagePath}`
        : 'Esy Sandbox';
    const curGroup = groups[groups.length - 1];
    if (groups.length === 0 || curGroup.header !== header) {
      const curGroup = {header, env: [item]};
      groups.push(curGroup);
    } else {
      curGroup.env.push(item);
    }
  }

  return Array.from(groups)
    .map(group => {
      const headerLines = [`# ${group.header}`];
      // TODO: add error rendering here
      // const errorLines = group.errors.map(err => {
      //   return '# [ERROR] ' + err;
      // });
      const envVarLines = group.env.map(item => {
        // TODO: escape " in values
        const exportLine = `export ${item.name}=${shell.doubleQuote(item.value)}`;
        return exportLine;
      });
      return headerLines.concat(envVarLines).join(EOL);
    })
    .join(EOL);
}

export function printEnvironmentMap(env: Map<string, string>): string {
  const lines = [];
  for (const [k, v] of env.entries()) {
    const exportLine = `export ${k}=${shell.doubleQuote(v)}`;
    lines.push(exportLine);
  }
  return lines.join(EOL);
}

export function evalEnvironment(env: Environment): Map<string, string> {
  const envMap = new Map();
  env.forEach(item => {
    const {value} = shell.expand(item.value, name => {
      const item = envMap.get(name);
      return item != null ? item : undefined;
    });
    if (value != null) {
      envMap.set(item.name, value);
    }
  });
  return envMap;
}
