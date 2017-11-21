/**
 * @flow
 */

import type {Reporter, BuildSpec, Config, BuildPlatform, StoreTree, Store} from './types';
import * as os from 'os';
import {STORE_BUILD_TREE, STORE_INSTALL_TREE, STORE_STAGE_TREE} from './constants';
import * as S from './store';
import * as path from './lib/path';
import * as crypto from './lib/crypto';

const NUM_CPUS = os.cpus().length;

function _create<Path: path.Path>(
  sandboxPath: Path,
  store: Store<Path>,
  localStore: Store<Path>,
  readOnlyStores,
  buildPlatform,
  reporter: Reporter,
): Config<Path> {
  const genStorePath = (tree: StoreTree, build: BuildSpec, segments: string[]) => {
    if (build.sourceType === 'immutable') {
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

  function getSourcePath(build: BuildSpec, ...segments): Path {
    return (path.join(build.sourcePath, ...segments): any);
  }

  const buildConfig: Config<Path> = {
    reporter,
    sandboxPath,
    store,
    localStore,
    buildPlatform,
    readOnlyStores,
    buildConcurrency: NUM_CPUS,
    requiresRootRelocation,

    getSourcePath,

    getRootPath: (build: BuildSpec, ...segments) => {
      if (requiresRootRelocation(build)) {
        return genStorePath(STORE_BUILD_TREE, build, segments);
      } else {
        return getSourcePath(build, ...segments);
      }
    },
    getBuildPath: (build: BuildSpec, ...segments) =>
      genStorePath(STORE_BUILD_TREE, build, segments),
    getInstallPath: (build: BuildSpec, ...segments) =>
      genStorePath(STORE_STAGE_TREE, build, segments),
    getFinalInstallPath: (build: BuildSpec, ...segments) =>
      genStorePath(STORE_INSTALL_TREE, build, segments),

    prettifyPath: (p: string) => {
      if (p.indexOf(store.path) === 0) {
        const relative = p.slice(store.path.length);
        return path.join(store.prettyPath, relative);
      } else {
        return p;
      }
    },

    getSandboxPath: (requests: Array<string>) => {
      // TODO: normalize requests?
      requests = requests.slice(0);
      requests.sort();
      const id = crypto.hash(requests.join(' '));
      // TODO: how to get prefix? is it availble in any config?
      const prefixPath = path.dirname(store.path);
      return path.join(prefixPath, 'sandbox', id);
    },
  };
  return buildConfig;
}

export function create(params: {
  reporter: Reporter,
  storePath: string,
  sandboxPath: string,
  buildPlatform: BuildPlatform,
  readOnlyStorePath: Array<string>,
}): Config<path.AbstractPath> {
  const {reporter, storePath, sandboxPath, buildPlatform, readOnlyStorePath} = params;
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
    reporter,
  );
}

export function createForPrefix(params: {
  reporter: Reporter,
  prefixPath: string,
  sandboxPath: string,
  buildPlatform: BuildPlatform,
  readOnlyStorePath: Array<string>,
}): Config<path.AbsolutePath> {
  const {reporter, prefixPath, sandboxPath, buildPlatform, readOnlyStorePath} = params;
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
    reporter,
  );
}
