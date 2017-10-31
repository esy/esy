/**
 * @flow
 */

import type {BuildSpec, StoreTree, Store} from './types';

import invariant from 'invariant';
import * as path from 'path';

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
export function forPath(storePath: string): Store {
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

/**
 * Create store based on a real prefix path.
 */
export function forPrefixPath(prefixPath: string): Store {
  prefixPath = sanitizePrefixPath(prefixPath);
  const storePath = getStorePathForPrefix(prefixPath);
  return forPath(storePath);
}

const REMOVE_TRAILING_SLASH_RE = /\/+$/g;
const ENVIRONMENT_VAR_RE = /\$[a-zA-Z_]/g;
const DOT_PATH_SEGMENT_RE = /\/\.\//g;
const DOT_DOT_PATH_SEGMENT_RE = /\/\.\.\//g;
const SANITIZE_SLASH_RE = /\/+/g;

/**
 * It is important for prefix to be a real path, not containing environment
 * variables other artefacts.
 */
function sanitizePrefixPath(prefix) {
  invariant(DOT_PATH_SEGMENT_RE.exec(prefix) == null, 'Invalid Esy prefix value');
  invariant(DOT_DOT_PATH_SEGMENT_RE.exec(prefix) == null, 'Invalid Esy prefix value');
  invariant(
    ENVIRONMENT_VAR_RE.exec(prefix) == null,
    'Esy prefix path should not contain environment variable references',
  );
  prefix = prefix.replace(REMOVE_TRAILING_SLASH_RE, '');
  prefix = prefix.replace(SANITIZE_SLASH_RE, '/');
  return prefix;
}

export function getStorePathForPrefix(prefix: string): string {
  const prefixLength = `${prefix}/${ESY_STORE_VERSION}`.length;
  const paddingLength = ESY_STORE_PADDING_LENGTH - prefixLength;
  invariant(
    paddingLength >= 0,
    `Esy prefix path is too deep in the filesystem, Esy won't be able to relocate artefacts`,
  );
  return `${prefix}/${ESY_STORE_VERSION}`.padEnd(ESY_STORE_PADDING_LENGTH, '_');
}
