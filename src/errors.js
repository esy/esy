/**
 * @flow
 */

import type {BuildConfigError} from './types';
import * as lang from './lib/lang.js';

export class SandboxError extends Error {
  errors: Array<BuildConfigError>;

  constructor(errors: Array<BuildConfigError>) {
    const message = 'SandboxError: Unable to configure snadbox';
    super(message);
    this.errors = errors;
    lang.fixupErrorSubclassing(this, SandboxError);
  }
}
