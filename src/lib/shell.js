/**
 * @flow
 */

import shellEscape from 'shell-escape';
import {substituteVariables} from 'var-expansion';

export function expand(input: string, resolve: string => ?string) {
  return substituteVariables(input, {
    env: resolve,
  });
}

export function singleQuote(v: string): string {
  return shellEscape([v]);
}

export function doubleQuote(v: string): string {
  return JSON.stringify(v);
}

export function quoteArgIfNeeded(arg: string): string {
  if (arg.indexOf(' ') === -1 && arg.indexOf("'") === -1 && arg.indexOf('"') === -1) {
    return arg;
  } else {
    return doubleQuote(arg);
  }
}
