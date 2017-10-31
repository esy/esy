/**
 * @flow
 */

import type {StoreTree} from './types';

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
export const STORE_BUILD_TREE: StoreTree = 'b';
export const STORE_INSTALL_TREE: StoreTree = 'i';
export const STORE_STAGE_TREE: StoreTree = 's';

/**
 * The current version of esy store, bump it whenever the store layout changes.
 */
export const ESY_STORE_VERSION = '3';

/**
 * This is a limit imposed by POSIX.
 *
 * Darwin is less strict with it but we found that Linux is.
 */
const MAX_SHEBANG_LENGTH = 127;

/**
 * This is how OCaml's ocamlrun executable path within store look like given the
 * currently used versioning schema.
 */
const OCAMLRUN_STORE_PATH = 'ocaml-n.00.000-########/bin/ocamlrun';

export const ESY_STORE_PADDING_LENGTH =
  MAX_SHEBANG_LENGTH -
  '!#'.length -
  `/${STORE_INSTALL_TREE}/${OCAMLRUN_STORE_PATH}`.length;
