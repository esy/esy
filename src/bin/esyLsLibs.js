/**
 * @flow
 */

import type {CommandContext, CommandInvocation} from './esy';
import type {BuildSpec, Config} from '../types';
import type {FormatBuildSpecTreeCtx, FormatBuildSpecQueueItem} from '../cli-utils';

import chalk from 'chalk';
import * as fs from '../lib/fs';
import {find} from '../graph';
import {spawn} from '../lib/child_process';
import {
  getBuildSpecPackages,
  getPackageLibraries,
  formatPackageInfo,
  formatTreeLine,
} from '../cli-utils';

import {getSandbox, getBuildConfig} from './esy';
import {Promise} from '../lib/Promise';

export default async function esyLsLibs(
  ctx: CommandContext,
  invocation: CommandInvocation,
) {
  const sandbox = await getSandbox(ctx);
  const config = await getBuildConfig(ctx);

  const {flags} = invocation.options;

  const ocamlfind = find(sandbox.root, cur => {
    return cur.name === '@opam/ocamlfind';
  });

  if (ocamlfind == null) {
    throw new Error(
      "We couldn't find ocamlfind, consider adding it to your devDependencies",
    );
  }

  const ocamlfindCmd = config.getFinalInstallPath(ocamlfind, 'bin', 'ocamlfind');
  const builtIns = await getPackageLibraries(config, ocamlfindCmd);

  const queue = getBuildSpecPackages(config, sandbox.root, !!flags.all, false);

  console.log(
    await formatBuildSpecTree(config, queue, {
      ocamlfind: ocamlfindCmd,
      builtIns,
    }),
  );
}

export const options = {
  flags: ['--all'],
};

type FormatBuildSpecOptions = {
  ocamlfind: string,
  builtIns: Array<string>,
};

async function formatBuildSpecTree(
  config: Config<*>,
  queue: Array<FormatBuildSpecQueueItem>,
  options: FormatBuildSpecOptions,
) {
  const lines = [];

  for (const cur of queue) {
    const {spec, ctx} = cur;

    const pkg = formatPackageInfo(config, spec, {...ctx, isSeen: ctx.level > 1});
    const libs = (await fs.exists(config.getFinalInstallPath(spec)))
      ? formatBuildLibrariesList(config, spec, options, {
          ...ctx,
          level: ctx.level + 1,
        })
      : Promise.resolve('');

    lines.push(pkg, libs);
  }

  const tree = await Promise.all(lines);
  return tree.filter(line => line.length > 0).join('\n');
}

async function formatBuildLibrariesList(
  config: Config<*>,
  spec: BuildSpec,
  options: FormatBuildSpecOptions,
  ctx: FormatBuildSpecTreeCtx,
) {
  const {level} = ctx;
  const {ocamlfind, builtIns} = options;
  const libraryLines = [];

  const libs = (await getPackageLibraries(config, ocamlfind, spec)).filter(
    lib => builtIns.indexOf(lib) < 0,
  );

  for (const lib of libs) {
    const isLast = lib === libs[libs.length - 1];

    const name = level > 2 ? chalk.yellow(`${lib}`) : chalk.yellow.bold(`${lib}`);
    const line = formatTreeLine(name, level, isLast);

    libraryLines.push(line);
  }

  return libraryLines.join('\n');
}
