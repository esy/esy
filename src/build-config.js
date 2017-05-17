/**
 * @flow
 */

import type {BuildSpec, BuildConfig} from './types';
import * as path from 'path';

export function createConfig(
  params: {
    storePath: string,
    sandboxPath: string,
  },
): BuildConfig {
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
