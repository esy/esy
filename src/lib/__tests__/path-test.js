/**
 * @flow
 */

import * as P from '../path';

test('creating absolute paths', function() {
  expect(P.absolute('/')).toBe('/');
  expect(P.absolute('/some')).toBe('/some');
  expect(P.absolute('/some/path')).toBe('/some/path');
  expect(() => P.absolute('some')).toThrowError();
  expect(() => P.absolute('some/path')).toThrowError();
  expect(() => P.absolute('')).toThrowError();
  expect(() => P.absolute('some/./path')).toThrowError();
  expect(() => P.absolute('some/../path')).toThrowError();
  expect(() => P.absolute('/some/../path')).toThrowError();
  expect(() => P.absolute('/some/./path')).toThrowError();
});

test('joining with absolute bases', function() {
  expect(P.join(P.absolute('/some'), P.concrete('path'))).toBe('/some/path');
});
