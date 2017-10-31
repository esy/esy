/**
 * @flow
 */

import type {BuildSpec, BuildConfig, BuildPlatform, StoreTree, Store} from './types';
import * as path from 'path';
import {STORE_BUILD_TREE, STORE_INSTALL_TREE, STORE_STAGE_TREE} from './constants';
import * as S from './store';

function _create({
  sandboxPath,
  store,
  localStore,
  readOnlyStores,
  buildPlatform,
}): BuildConfig {
  const genStorePath = (tree: StoreTree, build: BuildSpec, segments: string[]) => {
    if (build.shouldBePersisted) {
      return store.getPath(tree, build, ...segments);
    } else {
      return localStore.getPath(tree, build, ...segments);
    }
  };

  const buildConfig: BuildConfig = {
    sandboxPath,
    store,
    localStore,
    buildPlatform,
    readOnlyStores,

    getSourcePath: (build: BuildSpec, ...segments) => {
      return path.join(buildConfig.sandboxPath, build.sourcePath, ...segments);
    },
    getRootPath: (build: BuildSpec, ...segments) => {
      if (build.mutatesSourcePath) {
        return genStorePath(STORE_BUILD_TREE, build, segments);
      } else {
        return path.join(buildConfig.sandboxPath, build.sourcePath, ...segments);
      }
    },
    getBuildPath: (build: BuildSpec, ...segments) =>
      genStorePath(STORE_BUILD_TREE, build, segments),
    getInstallPath: (build: BuildSpec, ...segments) =>
      genStorePath(STORE_STAGE_TREE, build, segments),
    getFinalInstallPath: (build: BuildSpec, ...segments) =>
      genStorePath(STORE_INSTALL_TREE, build, segments),
  };
  return buildConfig;
}

export function create(params: {
  storePath: string,
  sandboxPath: string,
  buildPlatform: BuildPlatform,
  readOnlyStorePathList?: Array<string>,
}): BuildConfig {
  const {storePath, sandboxPath, buildPlatform, readOnlyStorePathList = []} = params;
  const store = S.forPath(storePath);
  const localStore = S.forPath(
    path.join(sandboxPath, 'node_modules', '.cache', '_esy', 'store'),
  );
  const readOnlyStores = readOnlyStorePathList.map(p => S.forPath(p));
  return _create({sandboxPath, store, localStore, readOnlyStores, buildPlatform});
}

export function createForPrefix(params: {
  prefixPath: string,
  sandboxPath: string,
  buildPlatform: BuildPlatform,
  readOnlyStorePathList?: Array<string>,
}) {
  const {prefixPath, sandboxPath, buildPlatform, readOnlyStorePathList = []} = params;
  const store = S.forPrefixPath(prefixPath);
  const localStore = S.forPath(
    path.join(sandboxPath, 'node_modules', '.cache', '_esy', 'store'),
  );
  const readOnlyStores = readOnlyStorePathList.map(p => S.forPath(p));
  return _create({sandboxPath, store, localStore, readOnlyStores, buildPlatform});
}
