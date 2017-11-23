/**
 * @flow
 */

import {defineTestCaseWithShell} from './utils';

defineTestCaseWithShell(
  'no-deps-in-source',
  `
    run esy build
    assertStdout "esy x no-deps-in-source" "no-deps-in-source"
  `,
);
