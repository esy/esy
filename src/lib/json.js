/**
 * @flow
 */

const jsonStableStringify = require('json-stable-stringify');

export function stableStringifyPretty(obj: any): string {
  return jsonStableStringify(obj, {space: '  '});
}
