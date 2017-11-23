/**
 * @flow
 */

import {defineTestCaseWithShell} from './utils';

defineTestCaseWithShell(
  'no-deps',
  `
    run esy build
    assertStdout "esy x no-deps" "no-deps"
  `,
);
