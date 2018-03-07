/**
 * Common utilities shared between command impementations.
 *
 * @flow
 */

import * as t from '../types.js';
import type {CommandContext} from './esy.js';
import outdent from 'outdent';
import {indent} from './esy';
import chalk from 'chalk';
import * as Env from '../environment.js';
import * as constants from '../constants.js';
import * as BuildTask from '../build-task.js';
import * as Sandbox from '../sandbox';
import * as Config from '../config.js';
import * as Graph from '../lib/graph.js';
import * as JSON from '../lib/json.js';
import * as fs from '../lib/fs.js';
import * as shell from '../lib/shell.js';
import * as path from '../lib/path.js';
import * as child from '../lib/child_process.js';

export async function exportBuild(
  ctx: CommandContext,
  config: t.Config<path.AbsolutePath>,
  build: t.BuildSpec,
  outputPath?: string,
) {
  const finalInstallPath = config.getInstallPath(build);
  const args = ['export-build', finalInstallPath];
  if (outputPath != null) {
    args.push(outputPath);
  }
  await child.spawn(constants.CURRENT_ESY_EXECUTABLE, args, {stdio: 'inherit'});
}

type File = {
  filename: Array<string>,
  contents: string,
  executable?: boolean,
};

export async function emitFileInto(outputPath: string, file: File) {
  const filename = path.join(outputPath, ...file.filename);
  await fs.mkdirp(path.dirname(filename));
  await fs.writeFile(filename, file.contents);
  if (file.executable) {
    // fs.constants only became supported in node 6.7 or so.
    const mode = fs.constants && fs.constants.S_IRWXU ? fs.constants.S_IRWXU : 448;
    await fs.chmod(filename, mode);
  }
}
