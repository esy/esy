/**
 * @flow
 */

import type {BuildSpec, StoreTree, Store} from './types';

import invariant from 'invariant';

import * as path from './lib/path';
import * as fs from './lib/fs';

import {
  STORE_BUILD_TREE,
  STORE_INSTALL_TREE,
  STORE_STAGE_TREE,
  ESY_STORE_VERSION,
  ESY_STORE_PADDING_LENGTH,
} from './constants';

/**
 * Create store.
 */
function forPath<K: path.Path>(storePath: K): Store<K> {
  return {
    path: storePath,

    getPath(tree: StoreTree, build: BuildSpec, ...segments: string[]) {
      return path.join(this.path, tree, build.id, ...segments);
    },

    has(build: BuildSpec): Promise<boolean> {
      return fs.exists(this.getPath(STORE_INSTALL_TREE, build));
    },
  };
}

export function forAbstractPath(storePath: string): Store<path.AbstractPath> {
  return forPath(path.abstract(storePath));
}

export function forAbsolutePath(storePath: string): Store<path.AbsolutePath> {
  return forPath(path.absolute(storePath));
}

/**
 * Create store based on a real prefix path.
 */
export function forPrefixPath(prefixPath: string): Store<path.AbsolutePath> {
  const conceretePrefixPath = path.absolute(prefixPath);
  const storePath = getStorePathForPrefix(conceretePrefixPath);
  return forPath(storePath);
}

export function getStorePathForPrefix(prefix: path.AbsolutePath): path.AbsolutePath {
  const prefixLength = path.length(path.join(prefix, ESY_STORE_VERSION));
  const paddingLength = ESY_STORE_PADDING_LENGTH - prefixLength;
  invariant(
    paddingLength >= 0,
    `Esy prefix path is too deep in the filesystem, Esy won't be able to relocate artefacts`,
  );
  const p = path.join(prefix, ESY_STORE_VERSION).padEnd(ESY_STORE_PADDING_LENGTH, '_');
  return (p: any);
}
