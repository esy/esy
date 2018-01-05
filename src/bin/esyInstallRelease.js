/**
 * @flow
 */

import * as t from '../types.js';
import type {CommandContext} from './esy.js';

import loudRejection from 'loud-rejection';

import * as fs from '../lib/fs.js';
import * as path from '../lib/path.js';
import * as child from '../lib/child_process.js';
import * as Store from '../store.js';
import * as constants from '../constants.js';
import {PromiseQueue} from '../lib/Promise.js';

const cwd = process.cwd();
const releasePackagePath = cwd;
const releaseExportPath = path.join(releasePackagePath, '_export');

export const noHeader = true;

export default async function esyInstallRelease(ctx: CommandContext) {
  if (!await fs.exists(releaseExportPath)) {
    ctx.error('malformed release');
  }

  const store = Store.forPrefixPath(releasePackagePath);

  if (await fs.exists(store.path)) {
    ctx.reporter.info('release already installed, exiting...');
    return;
  }

  const queue = new PromiseQueue({concurrency: 30});

  const builds = await fs.walk(releaseExportPath);

  await Store.initStore(store);
  await Promise.all(
    builds.map(async file => {
      await importBuild(ctx, file.absolute, store);
    }),
  );

  ctx.reporter.info('done');
}

async function importBuild(ctx, filename: string, store: t.Store<*>) {
  const buildId = path.basename(filename).replace(/\.tar\.gz$/g, '');
  ctx.reporter.info(`importing: ${buildId}`);
  const stagePath = await fs.mkdtemp('release');
  const buildPath = path.join(stagePath, buildId);
  await child.spawn('tar', ['xzf', filename, '-C', stagePath], {stdio: 'inherit'});
  const prevStorePrefix = await fs.readFile(path.join(buildPath, '_esy', 'storePrefix'));
  await rewritePaths(buildPath, prevStorePrefix, store.path);
  await fs.rename(
    buildPath,
    path.join(store.path, constants.STORE_INSTALL_TREE, buildId),
  );
}

async function rewritePaths(path, from, to) {
  const rewriteQueue = new PromiseQueue({concurrency: 20});
  const files = await fs.walk(path);
  await Promise.all(
    files.map(file =>
      rewriteQueue.add(async () => {
        if (file.stats.isSymbolicLink()) {
          await rewritePathInSymlink(file.absolute, from, to);
        } else {
          await rewritePathInFile(file.absolute, from, to);
        }
      }),
    ),
  );
}

async function rewritePathInFile(filename: string, origPath: string, destPath: string) {
  const stat = await fs.stat(filename);
  if (!stat.isFile()) {
    return;
  }
  const content = await fs.readFileBuffer(filename);
  let offset = content.indexOf(origPath);
  const needRewrite = offset > -1;
  while (offset > -1) {
    content.write(destPath, offset);
    offset = content.indexOf(origPath);
  }
  if (needRewrite) {
    await fs.writeFile(filename, content);
  }
}

async function rewritePathInSymlink(
  filename: string,
  origPath: string,
  destPath: string,
) {
  const stat = await fs.lstat(filename);
  if (!stat.isSymbolicLink()) {
    return;
  }
  const linkPath = await fs.readlink(filename);
  if (linkPath.indexOf(origPath) !== 0) {
    return;
  }
  const nextTargetPath = path.join(destPath, path.relative(origPath, linkPath));
  await fs.unlink(filename);
  await fs.fsSymlink(nextTargetPath, filename);
}
