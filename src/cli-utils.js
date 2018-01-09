/*
 * @flow
 */

import type {BuildSpec, Config} from './types';
import chalk from 'chalk';
import {spawn} from './lib/child_process';
import * as fs from './lib/fs';
import * as path from './lib/path';

export type FormatBuildSpecTreeCtx = {
  level: number,
  isSeen: boolean,
  isLast: boolean,
};

export type FormatBuildSpecQueueItem = {
  spec: BuildSpec,
  ctx: FormatBuildSpecTreeCtx,
  path: string,
};

export function getBuildSpecPackages(
  config: Config<*>,
  root: BuildSpec,
  includeDeps?: boolean = true,
  includeSeen?: boolean = true,
): FormatBuildSpecQueueItem[] {
  const specsQueue = [];
  const seen = new Set();

  const queue = [
    {
      spec: root,
      ctx: {
        level: 0,
        isSeen: false,
        isLast: true,
      },
      path: '#',
    },
  ];

  while (queue.length > 0) {
    const cur = queue.shift();
    const {spec, ctx, path} = cur;

    const isSeen = seen.has(spec.id);
    if (isSeen && !includeSeen) {
      continue;
    }
    const {level} = ctx;

    specsQueue.push({spec, ctx: {...ctx, isSeen}, path});
    seen.add(spec.id);

    if (includeDeps || level < 1) {
      const deps = Array.from(spec.dependencies.values());
      let idx = 0;
      for (const dep of deps) {
        const isLast = dep === deps[deps.length - 1];
        queue.push({
          spec: dep,
          ctx: {level: level + 1, isSeen: false, isLast},
          path: `${path}${idx++}${dep.name}#`,
        });
      }
    }
  }

  return specsQueue.sort((a, b) => {
    return a.path.localeCompare(b.path);
  });
}

export async function getPackageLibraries(
  config: Config<*>,
  ocamlfind: string,
  spec: ?BuildSpec,
): Promise<Array<string>> {
  const result = await spawn(ocamlfind, ['list'], {
    env: {
      OCAMLPATH: spec != null ? config.getInstallPath(spec, 'lib') : '',
    },
  });

  return result.split('\n').map(line => {
    const [lib, ...version] = line.split(' ');
    return lib;
  });
}

export async function formatPackageInfo(
  config: Config<*>,
  spec: BuildSpec,
  ctx: FormatBuildSpecTreeCtx,
) {
  const {level, isSeen, isLast} = ctx;

  const version = chalk.grey(`@${spec.version}`);

  let name = `${spec.name}${version}`;
  if (level > 0 && spec.sourceType === 'transient') {
    const loc = path.relative(config.sandboxPath, config.getSourcePath(spec));
    name = `${name} ${chalk.grey(loc)}`;
  }

  const info = await formatBuildInfo(config, spec);
  name = `${name} ${info}`;

  if (isSeen) {
    name = chalk.grey(name);
  }

  return formatTreeLine(name, level, isLast);
}

export async function formatBuildInfo(config: Config<*>, spec: BuildSpec) {
  const buildStatus = (await fs.exists(config.getInstallPath(spec)))
    ? chalk.green('[built]')
    : chalk.blue('[build pending]');
  let info = [buildStatus];
  if (spec.sourceType === 'transient' || spec.sourceType === 'root') {
    info.push(chalk.blue('[local source]'));
  }
  return info.join(' ');
}

export function formatTreeLine(
  name: string,
  level: number,
  isLast: boolean,
  addPrefix?: boolean = true,
) {
  const prefix = addPrefix ? (level === 0 ? '' : isLast ? '└── ' : '├── ') : '';
  const line = `${prefix}${name}`;
  return line.padStart(line.length + (level - 1) * 4, '│   ');
}
