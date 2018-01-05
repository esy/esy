/**
 * @flow
 */

const jsonStableStringify = require('json-stable-stringify');

export function stableStringifyPretty(obj: any): string {
  return jsonStableStringify(obj, {space: '  '});
}

export const parse = JSON.parse;
export const stringify = JSON.stringify;
