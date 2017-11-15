/**
 * @flow
 */

import type {SandboxType} from './types';

export function sandboxType(v: mixed): SandboxType {
  switch (v) {
    case 'global':
    case 'project':
      return v;
    default:
      throw new Error('sandboxType: expected "global" or "project"');
  }
}
