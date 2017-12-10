/*
 * @flow
 */

import type {BuildSpec, Config} from './types';
import chalk from 'chalk';
import * as fs from './lib/fs';

export async function formatBuildInfo(config: Config<*>, spec: BuildSpec) {
  const buildStatus = (await fs.exists(config.getFinalInstallPath(spec)))
    ? chalk.green('[built]')
    : chalk.blue('[build pending]');
  let info = [buildStatus];
  if (spec.sourceType === 'transient' || spec.sourceType === 'root') {
    info.push(chalk.blue('[local source]'));
  }
  return info.join(' ');
}
