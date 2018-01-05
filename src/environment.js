/**
 * @flow
 */

import type {Environment, EnvironmentBinding} from './types';

import * as shell from './lib/shell.js';
import * as os from 'os';
import outdent from 'outdent';

// X platform newline
const EOL = os.EOL;

/**
 * Print environment as a bash script.
 */
export function printEnvironment(env: Environment) {
  const groupsByBuild = new Map();

  const groups = [];

  for (const item of env) {
    const header =
      item.origin != null
        ? `${item.origin.name}@${item.origin.version} (at ${item.origin.packagePath})`
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
      const headerLines = [
        outdent`

          #
          # ${group.header}
          #
        `,
      ];
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

type EvalEnvironment = Map<string, string>;

/**
 * Eval environment into a mapping of key-values.
 */
export function evalEnvironment(env: Environment): EvalEnvironment {
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

export function printEvalEnvironment(env: EvalEnvironment) {
  const lines = [];
  for (const [k, v] in env.entries()) {
    if (v == null) {
      continue;
    } else if (Array.isArray(v)) {
      if (v.length === 0) {
        lines.push(`export ${k}='';`);
      } else {
        const items = v.map(shell.doubleQuote);
        lines.push(`export ${k}=(${items.join(' ')});`);
      }
    } else {
      lines.push(`export ${k}=${shell.doubleQuote(v)};`);
    }
  }
  return lines.join('\n');
}
