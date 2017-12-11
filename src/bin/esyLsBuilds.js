/**
 * @flow
 */

import type {CommandContext} from './esy';
import type {BuildSpec, Config} from '../types';
import type {FormatBuildSpecQueueItem} from '../cli-utils';

import {formatPackageInfo, getBuildSpecPackages} from '../cli-utils';

import {getSandbox, getBuildConfig} from './esy';
import {Promise} from '../lib/Promise';

export default async function esyLsBuilds(ctx: CommandContext) {
  const sandbox = await getSandbox(ctx);
  const config = await getBuildConfig(ctx);

  const queue = getBuildSpecPackages(config, sandbox.root);

  console.log(await formatBuildSpecTree(config, queue));
}

async function formatBuildSpecTree(
  config: Config<*>,
  queue: Array<FormatBuildSpecQueueItem>,
) {
  const lines = [];

  for (const cur of queue) {
    const {spec, ctx} = cur;
    const pkg = formatPackageInfo(config, spec, ctx);
    lines.push(pkg);
  }

  const tree = await Promise.all(lines);
  return tree.join('\n');
}
