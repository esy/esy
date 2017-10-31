/**
 * @flow
 */

import invariant from 'invariant';
const path = require('path');

/**
 * Absolute path.
 */
export opaque type AbsolutePath: ConcretePath = string;

/**
 * Path with no `.` or `..` or any bash variables in it.
 */
export opaque type ConcretePath: Path = string;

/**
 * Path which can contain bash/make variables in it, cannot be used in
 * filesystem operations.
 */
export opaque type AbstractPath: Path = string;

export opaque type Path = AbsolutePath | ConcretePath | AbstractPath;

export function absolute(p: string): AbsolutePath {
  p = sanitizeAbsolutePath(p);
  return p;
}

export function concrete(p: string): ConcretePath {
  p = sanitizeConcretePath(p);
  return p;
}

export function abstract(p: string): AbstractPath {
  return p;
}

export function join<B: Path, P: ConcretePath>(base: B, ...p: P[]): B {
  return (path.join(base, ...p): any);
}

export function length(p: ConcretePath): number {
  return p.length;
}

export function toString(p: ConcretePath): string {
  return p;
}

function sanitizeAbsolutePath(p) {
  p = sanitizeConcretePath(p);
  invariant(path.isAbsolute(p), 'Should be absolute path but got: %s', p);
  return p;
}

function sanitizeConcretePath(p) {
  // NOTE: regexpes are stateful, this is why we are creating them here.
  // Consider resetting their state after matching instead.
  const REMOVE_TRAILING_SLASH_RE = /\/+$/g;
  const ENVIRONMENT_VAR_RE = /\$[a-zA-Z_]/g;
  const DOT_PATH_SEGMENT_RE = /\/\.\//g;
  const DOT_DOT_PATH_SEGMENT_RE = /\/\.\.\//g;
  const SANITIZE_SLASH_RE = /\/+/g;

  invariant(
    DOT_PATH_SEGMENT_RE.exec(p) == null,
    'Should not contain "." segments: %s',
    p,
  );
  invariant(
    DOT_DOT_PATH_SEGMENT_RE.exec(p) == null,
    'Should not contain ".." segments: %s',
    p,
  );
  invariant(
    ENVIRONMENT_VAR_RE.exec(p) == null,
    'Path should not contain variable references: %s',
    p,
  );
  p = path.normalize(p);
  p = p.replace(REMOVE_TRAILING_SLASH_RE, '');
  p = p === '' ? '/' : p;
  return p;
}
