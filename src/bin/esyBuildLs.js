/**
 * @flow
 */

import type {CommandContext} from './esy';
import type {BuildSpec, Config} from '../types';

import chalk from 'chalk';
import * as fs from '../lib/fs';
import * as path from '../lib/path';

import {getSandbox, getBuildConfig} from './esy';

export default async function esyBuildLs(ctx: CommandContext) {
  const sandbox = await getSandbox(ctx);
  const config = await getBuildConfig(ctx);
  console.log(await formatBuildSpecTree(config, sandbox.root));
}

type FormatBuildSpecTreeCtx = {
  indent: number,
  seen: Set<string>,
  isLast: boolean,
};

async function formatBuildSpecTree(
  config: Config<*>,
  spec: BuildSpec,
  ctx?: FormatBuildSpecTreeCtx = {indent: 0, seen: new Set(), isLast: false},
) {
  const {indent, seen, isLast} = ctx;
  const dependenciesLines = [];

  const hasSeenIt = seen.has(spec.id);
  if (!hasSeenIt) {
    seen.add(spec.id);
    const dependencies = Array.from(spec.dependencies.values());
    for (const dep of dependencies) {
      const isLast = dep === dependencies[dependencies.length - 1];
      dependenciesLines.push(
        formatBuildSpecTree(config, dep, {indent: indent + 1, seen, isLast}),
      );
    }
  }

  const version = chalk.grey(`@${spec.version}`);
  let name = `${spec.name}${version}`;
  if (indent > 0 && spec.sourceType === 'transient') {
    const loc = path.relative(config.sandboxPath, config.getSourcePath(spec));
    name = `${name} ${chalk.grey(loc)}`;
  }
  const info = await formatBuildInfo(config, spec);
  name = `${name} ${info}`;
  if (hasSeenIt) {
    name = chalk.grey(name);
  }

  const prefix = indent === 0 ? '' : isLast ? '└── ' : '├── ';
  let line = `${prefix}${name}`;
  line = line.padStart(line.length + (indent - 1) * 4, '│   ');

  return [line].concat(await Promise.all(dependenciesLines)).join('\n');
}

async function formatBuildInfo(config, spec) {
  const buildStatus = (await fs.exists(config.getFinalInstallPath(spec)))
    ? chalk.green('[built]')
    : chalk.blue('[build pending]');
  let info = [buildStatus];
  if (spec.sourceType === 'transient') {
    info.push(chalk.blue('[local source]'));
  }
  return info.join(' ');
}
