/**
 * @flow
 */

import outdent from 'outdent';
import * as lang from './lib/lang.js';
import * as types from './types.js';

/**
 * Error happened b/c of invalid configuration or usage.
 */
export class UsageError extends Error {
  constructor(message: string) {
    super(message);
    lang.fixupErrorSubclassing(this, UsageError);
  }
}

/**
 * Usage error specific to the concrete build.
 */
export class BuildConfigError extends UsageError {
  spec: types.BuildSpec;
  reason: string;

  constructor(spec: types.BuildSpec, reason: string) {
    const message = outdent`
      Package ${spec.name} (at ${spec.packagePath}):
      ${reason}
    `;
    super(message);
    this.spec = spec;
    this.reason = reason;
    lang.fixupErrorSubclassing(this, BuildConfigError);
  }
}
