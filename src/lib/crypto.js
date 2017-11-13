/**
 * @flow
 */

const crypto = require('crypto');

export function hash(content: string, type: string = 'md5'): string {
  return crypto
    .createHash(type)
    .update(content)
    .digest('hex');
}
