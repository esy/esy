/**
 * @flow
 */

import type {BuildSpec, BuildConfig} from './types';
import * as path from 'path';

// The current version of esy store, bump it whenever the store layout changes.
// We also have the same constant hardcoded into bin/esy executable for perf
// reasons (we don't want to spawn additional processes to read from there).
//
// XXX: Update bin/esy if you change it.
// TODO: We probably still want this be the source of truth so figure out how to
// put this into bin/esy w/o any perf penalties.
export const ESY_STORE_VERSION = '3.x.x';

export function createConfig(params: {
  storePath: string,
  sandboxPath: string,
}): BuildConfig {
  const {storePath, sandboxPath} = params;
  const localStorePath = path.join(
    sandboxPath,
    'node_modules',
    '.cache',
    '_esy',
    'store',
  );
  const genPath = (build: BuildSpec, tree: string, segments: string[]) => {
    if (build.shouldBePersisted) {
      return path.join(storePath, tree, build.id, ...segments);
    } else {
      return path.join(localStorePath, tree, build.id, ...segments);
    }
  };

  const buildConfig: BuildConfig = {
    sandboxPath,
    storePath,
    localStorePath,
    getSourcePath: (build: BuildSpec, ...segments) => {
      return path.join(buildConfig.sandboxPath, build.sourcePath, ...segments);
    },
    getRootPath: (build: BuildSpec, ...segments) => {
      if (build.mutatesSourcePath) {
        return genPath(build, '_build', segments);
      } else {
        return path.join(buildConfig.sandboxPath, build.sourcePath, ...segments);
      }
    },
    getBuildPath: (build: BuildSpec, ...segments) => genPath(build, '_build', segments),
    getInstallPath: (build: BuildSpec, ...segments) =>
      genPath(build, '_insttmp', segments),
    getFinalInstallPath: (build: BuildSpec, ...segments) =>
      genPath(build, '_install', segments),
  };
  return buildConfig;
}
