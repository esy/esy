/**
 * @flow
 */

import type {BuildSpec, BuildConfig, BuildPlatform} from './types';
import * as path from 'path';
import invariant from 'invariant';

// The current version of esy store, bump it whenever the store layout changes.
// We also have the same constant hardcoded into bin/esy executable for perf
// reasons (we don't want to spawn additional processes to read from there).
//
// XXX: Update bin/esy if you change it.
// TODO: We probably still want this be the source of truth so figure out how to
// put this into bin/esy w/o any perf penalties.
export const ESY_STORE_VERSION = '3.x.x';

/**
 * Constants for tree names inside stores. We keep them short not to exhaust
 * available shebang length as install tree will be there.
 */
export const STORE_BUILD_TREE = 'b';
export const STORE_INSTALL_TREE = 'i';
export const STORE_STAGE_TREE = 's';

export function create(params: {
  storePath: string,
  sandboxPath: string,
  buildPlatform: BuildPlatform,
}): BuildConfig {
  const {storePath, sandboxPath, buildPlatform} = params;
  const localStorePath = path.join(
    sandboxPath,
    'node_modules',
    '.cache',
    '_esy',
    'store',
  );
  const genStorePath = (build: BuildSpec, tree: string, segments: string[]) => {
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
    buildPlatform,
    getSourcePath: (build: BuildSpec, ...segments) => {
      return path.join(buildConfig.sandboxPath, build.sourcePath, ...segments);
    },
    getRootPath: (build: BuildSpec, ...segments) => {
      if (build.mutatesSourcePath) {
        return genStorePath(build, STORE_BUILD_TREE, segments);
      } else {
        return path.join(buildConfig.sandboxPath, build.sourcePath, ...segments);
      }
    },
    getBuildPath: (build: BuildSpec, ...segments) =>
      genStorePath(build, STORE_BUILD_TREE, segments),
    getInstallPath: (build: BuildSpec, ...segments) =>
      genStorePath(build, STORE_STAGE_TREE, segments),
    getFinalInstallPath: (build: BuildSpec, ...segments) =>
      genStorePath(build, STORE_INSTALL_TREE, segments),
  };
  return buildConfig;
}

const ENVIRONMENT_VAR_RE = /\$[a-zA-Z_]/;

export function createForPrefix(params: {
  prefixPath: string,
  sandboxPath: string,
  buildPlatform: BuildPlatform,
}) {
  // I'm not sure we can make this check more exhaustive. But this is a good
  // sanity check which prevents passing non-real looking paths as `prefixPath`.
  invariant(
    ENVIRONMENT_VAR_RE.exec(params.prefixPath) == null,
    'Esy prefix path should not contain environment variable references, but got: %s',
    params.prefixPath,
  );
  const storePath = getStorePathForPrefix(params.prefixPath);
  return create({
    storePath,
    sandboxPath: params.sandboxPath,
    buildPlatform: params.buildPlatform,
  });
}

export function getStorePathForPrefix(prefix: string): string {
  const prefixLength = `${prefix}/${ESY_STORE_VERSION}`.length;
  const paddingLength = DESIRED_ESY_STORE_PATH_LENGTH - prefixLength;
  invariant(
    paddingLength >= 0,
    `Esy prefix path is too deep in the filesystem, Esy won't be able to relocate artefacts`,
  );
  return `${prefix}/${ESY_STORE_VERSION}`.padEnd(DESIRED_ESY_STORE_PATH_LENGTH, '_');
}

const DESIRED_SHEBANG_PATH_LENGTH = 127 - '!#'.length;
const PATH_LENGTH_CONSUMED_BY_OCAMLRUN = '/i/ocaml-n.00.0-########/bin/ocamlrun'.length;
export const DESIRED_ESY_STORE_PATH_LENGTH =
  DESIRED_SHEBANG_PATH_LENGTH - PATH_LENGTH_CONSUMED_BY_OCAMLRUN;
