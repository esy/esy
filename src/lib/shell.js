/**
 * @flow
 */

import shellEscape from 'shell-escape';

export function singleQuote(v: string): string {
  return shellEscape([v]);
}

export function doubleQuote(v: string): string {
  return JSON.stringify(v);
}
