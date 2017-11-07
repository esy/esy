/**
 * @flow
 */

import type {BuildSpec, Config, BuildPlatform, StoreTree, Store} from './types';
import {STORE_BUILD_TREE, STORE_INSTALL_TREE, STORE_STAGE_TREE} from './constants';
import * as S from './store';
import * as path from './lib/path';

function _create<Path: path.Path>(
  sandboxPath: Path,
  store: Store<Path>,
  localStore: Store<Path>,
  readOnlyStores,
  buildPlatform,
): Config<Path> {
  const genStorePath = (tree: StoreTree, build: BuildSpec, segments: string[]) => {
    if (build.shouldBePersisted) {
      return store.getPath(tree, build, ...segments);
    } else {
      return localStore.getPath(tree, build, ...segments);
    }
  };

  const requiresRootRelocation = ({buildType, sourceType}: BuildSpec) => {
    if (buildType === 'in-source') {
      return true;
    }
    if (buildType === '_build' && sourceType !== 'root') {
      return true;
    }
    return false;
  };

  const buildConfig = {
    sandboxPath,
    store,
    localStore,
    buildPlatform,
    readOnlyStores,

    requiresRootRelocation,

    getSourcePath: (build: BuildSpec, ...segments) => {
      return path.join(buildConfig.sandboxPath, build.sourcePath, ...segments);
    },
    getRootPath: (build: BuildSpec, ...segments) => {
      if (requiresRootRelocation(build)) {
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

    prettifyPath: (p: string) => {
      if (store.path.indexOf(p) === -1) {
        const relative = p.slice(store.path.length);
        return path.join(store.prettyPath, relative);
      } else {
        return p;
      }
    },
  };
  return buildConfig;
}

export function create(params: {
  storePath: string,
  sandboxPath: string,
  buildPlatform: BuildPlatform,
  readOnlyStorePath: Array<string>,
}): Config<path.AbstractPath> {
  const {storePath, sandboxPath, buildPlatform, readOnlyStorePath} = params;
  const store = S.forAbstractPath(storePath);
  const localStore = S.forAbstractPath(
    path.join(sandboxPath, 'node_modules', '.cache', '_esy', 'store'),
  );
  const readOnlyStores = readOnlyStorePath.map(p => S.forAbsolutePath(p));
  return _create(
    path.abstract(sandboxPath),
    store,
    localStore,
    readOnlyStores,
    buildPlatform,
  );
}

export function createForPrefix(params: {
  prefixPath: string,
  sandboxPath: string,
  buildPlatform: BuildPlatform,
  readOnlyStorePath: Array<string>,
}): Config<path.AbsolutePath> {
  const {prefixPath, sandboxPath, buildPlatform, readOnlyStorePath} = params;
  const store = S.forPrefixPath(prefixPath);
  const localStore = S.forAbsolutePath(
    path.join(sandboxPath, 'node_modules', '.cache', '_esy', 'store'),
  );
  const readOnlyStores = readOnlyStorePath.map(p => S.forAbsolutePath(p));
  return _create(
    path.absolute(sandboxPath),
    store,
    localStore,
    readOnlyStores,
    buildPlatform,
  );
}
