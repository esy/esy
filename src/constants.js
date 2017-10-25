/**
 * @flow
 */

/**
 * Names of the symlinks to build and install trees of the sandbox.
 */
export const BUILD_TREE_SYMLINK = '_esybuild';
export const INSTALL_TREE_SYMLINK = '_esyinstall';

/**
 * Name of the tree used to store releases for the sandbox.
 */
export const RELEASE_TREE = '_release';

/**
 * Constants for tree names inside stores. We keep them short not to exhaust
 * available shebang length as install tree will be there.
 */
export const STORE_BUILD_TREE = 'b';
export const STORE_INSTALL_TREE = 'i';
export const STORE_STAGE_TREE = 's';

// The current version of esy store, bump it whenever the store layout changes.
// We also have the same constant hardcoded into bin/esy executable for perf
// reasons (we don't want to spawn additional processes to read from there).
//
// XXX: Update bin/esy if you change it.
// TODO: We probably still want this be the source of truth so figure out how to
// put this into bin/esy w/o any perf penalties.
export const ESY_STORE_VERSION = '3.x.x';

const DESIRED_SHEBANG_PATH_LENGTH = 127 - '!#'.length;
const PATH_LENGTH_CONSUMED_BY_OCAMLRUN = '/i/ocaml-n.00.000-########/bin/ocamlrun'.length;
export const DESIRED_ESY_STORE_PATH_LENGTH =
  DESIRED_SHEBANG_PATH_LENGTH - PATH_LENGTH_CONSUMED_BY_OCAMLRUN;
