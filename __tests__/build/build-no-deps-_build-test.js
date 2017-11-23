/**
 * @flow
 */

import {defineTestCaseWithShell} from './utils';

defineTestCaseWithShell(
  'no-deps-_build',
  `
    run esy build
    run ls
    run ls _build
    run esy x no-deps-_build
    assertStdout "esy x no-deps-_build" "no-deps-_build"
  `,
);
